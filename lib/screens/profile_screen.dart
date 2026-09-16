import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import 'paywall_screen.dart';
import '../widgets/sandik_error_view.dart';
import '../theme/sandik.dart';
import '../utils/polling.dart';
import 'recap_screen.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/friendly_error.dart';
import '../utils/partner_code_formatter.dart';
import 'settings_screen.dart';
import '../widgets/leaderboard_hero_card.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/tour_anchor.dart';
import '../l10n/l10n.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

/// Ortaklık akışına özel markaya uygun mesaj gösterimi.
/// Sunucudan gelen kod-bazlı Türkçe mesajları tanır ve bağlama göre
/// bilgi/hata rozeti seçer (raw exception göstermez).
Future<void> _showPartnerMsg(
  BuildContext context,
  String rawMessage, {
  required bool isError,
}) async {
  if (!context.mounted) return;
  final msg = rawMessage.replaceFirst(RegExp(r'^Exception:\s*'), '');

  if (!isError) {
    await showAppSuccess(context, title: context.l10n.doneTitle, message: msg);
    return;
  }

  // Belirli senaryolar için bilgi rozeti (hata değil bilgilendirme):
  if (msg.contains('zaten ortağın')) {
    await showAppInfo(context, title: context.l10n.alreadyPartners, message: msg);
    return;
  }
  if (msg.contains('Kendi ürettiğin')) {
    await showAppInfo(context, title: context.l10n.ownCode, message: msg);
    return;
  }
  if (msg.contains('süresi dolmuş')) {
    await showAppInfo(context, title: context.l10n.expiredTitle, message: msg);
    return;
  }
  // Rate limit bir arıza değil, geçici bekleme — mesaj kalan süreyi
  // taşır ("... 4 dakika sonra tekrar deneyin"), bu yüzden genel
  // "Bir sorun oluştu" başlığı yerine kendi başlığıyla gösterilir.
  if (msg.contains('Çok fazla başarısız deneme')) {
    await showAppInfo(context, title: context.l10n.waitABit, message: msg);
    return;
  }
  await showSandikDialog(
    context: context,
    kind: SandikDialogKind.error,
    title: context.l10n.somethingWentWrong,
    message: msg,
  );
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _codeCtrl = TextEditingController();
  String? _generatedCode;
  bool _generating = false;
  bool _submitting = false;
  bool _busy = false;

  /// Rate limit bitiş anı ve saniyede bir tetiklenen geri sayım.
  /// Kalan süre yalnızca hata diyaloğunda gösterilirse kullanıcı
  /// diyaloğu kapattığı anda ne kadar bekleyeceğini unutur; bu yüzden
  /// alanın altında canlı olarak da gösterilir.
  DateTime? _rateLimitedUntil;
  Timer? _rateLimitTicker;

  String? _pendingInviteId;
  String? _pendingPartnerName;
  BackoffPoller? _poll;

  @override
  void initState() {
    super.initState();
    _restoreRateLimitCountdown();
  }

  /// Kilit önceki oturumda oluşmuş olabilir; ekran açılır açılmaz
  /// kalan süreyi göster (kullanıcı bir şey denemeden de görsün).
  Future<void> _restoreRateLimitCountdown() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final remaining =
        await AuthService.instance.partnerCodeLockRemainingSeconds(user.id);
    if (!mounted || remaining <= 0) return;
    _startRateLimitCountdown(remaining);
  }

  @override
  void dispose() {
    _rateLimitTicker?.cancel();
    _codeCtrl.dispose();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _showMsg(String msg, {bool isError = false}) =>
      _showPartnerMsg(context, msg, isError: isError);

  Future<void> _generateCode() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    setState(() {
      _generating = true;
      _busy = true;
    });
    // Sözlük await'lerden ÖNCE çözülür: `context` async boşluğun ardında
    // kullanılamaz (`use_build_context_synchronously`).
    final kopyalandi = context.l10n.codeCopied;
    try {
      final code = await AuthService.instance.generatePartnerCode(user.id);
      setState(() => _generatedCode = code);
      await Clipboard.setData(ClipboardData(text: code));
      await _showMsg(kopyalandi);
    } catch (e) {
      await _showMsg(friendlyError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _submitCode() async {
    // Formatter alanı zaten normalize eder; burada tekrar geçirmek
    // programatik doldurma (yapıştırma, otomatik doldurma, test) gibi
    // formatter'ı atlayan yolları da kapsar.
    final code = PartnerCodeInputFormatter.format(_codeCtrl.text);
    if (code.isEmpty) return;
    setState(() {
      _submitting = true;
      _busy = true;
    });
    try {
      final result = await ref.read(partnersProvider.notifier).submitCode(code);
      _codeCtrl.clear();
      setState(() {
        _pendingInviteId = result.inviteId;
        _pendingPartnerName = result.partnerName;
      });
      _startPolling(result.inviteId);
    } on RateLimitedException catch (e) {
      _startRateLimitCountdown(e.retryAfterSeconds);
      if (mounted) {
        // Dialog geri sayımı CANLI göstersin: sabit metin, kullanıcı
        // dialogu okurken bile eskiyordu. Süre dolunca kendini kapatır.
        await showSandikDialog(
          context: context,
          kind: SandikDialogKind.info,
          title: context.l10n.waitABit,
          message: friendlyError(e),
          liveMessage: () {
            final kalan = _rateLimitRemaining;
            if (kalan <= 0) return null; // dialog kapanır
            return context.l10n.tooManyFailedAttempts(_rateLimitLabel);
          },
        );
      }
    } catch (e) {
      await _showMsg(friendlyError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _busy = false;
        });
      }
    }
  }

  /// Rate limit geri sayımını başlatır. Süre dolunca alan kendiliğinden
  /// açılır — kullanıcının ekrandan çıkıp girmesi gerekmez.
  void _startRateLimitCountdown(int seconds) {
    _rateLimitTicker?.cancel();
    if (!mounted || seconds <= 0) return;
    setState(() {
      _rateLimitedUntil = DateTime.now().add(Duration(seconds: seconds));
    });
    _rateLimitTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_rateLimitRemaining <= 0) {
        t.cancel();
        setState(() => _rateLimitedUntil = null);
      } else {
        setState(() {}); // kalan süreyi tazele
      }
    });
  }

  /// Kalan saniye; kilit yoksa 0.
  int get _rateLimitRemaining {
    final until = _rateLimitedUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// "4:05" / "45 saniye" biçiminde kalan süre etiketi.
  String get _rateLimitLabel {
    final s = _rateLimitRemaining;
    if (s <= 60) return '$s saniye';
    final dk = s ~/ 60;
    final sn = s % 60;
    return '$dk:${sn.toString().padLeft(2, '0')} dakika';
  }

  void _startPolling(String inviteId) {
    _poll?.cancel();
    // Sabit 3 sn yerine geri çekilmeli yoklama (3→15 sn, en çok 10 dk).
    // Gerçek zamanlı bildirim ayrıca `PartnerInviteListenerService`'ten
    // geliyor; bu yoklama yalnızca push/realtime kaçarsa yedek.
    _poll = BackoffPoller(
      check: () async {
        if (!mounted) return true;
        final status =
            await SupabaseService.instance.getInviteStatus(inviteId);
        if (status == 'accepted') {
          await ref.read(partnersProvider.notifier).refresh();
          unawaited(ref.read(allPartnerAssetsProvider.notifier).reload());
          if (mounted) {
            final name = _pendingPartnerName;
            setState(() {
              _pendingInviteId = null;
              _pendingPartnerName = null;
            });
            await _showMsg(context.l10n.partnershipCreated(name ?? ''));
          }
          return true;
        }
        if (status == 'rejected') {
          if (mounted) {
            setState(() {
              _pendingInviteId = null;
              _pendingPartnerName = null;
            });
            await _showMsg(context.l10n.requestRejected, isError: true);
          }
          return true;
        }
        return false;
      },
    )..start();
  }

  Future<void> _cancelPending() async {
    final inviteId = _pendingInviteId;
    if (inviteId == null) return;

    final confirm = await showSandikConfirm(
      context: context,
      title: context.l10n.cancelInviteTitle,
      message: context.l10n.cancelInviteBody,
      confirmLabel: context.l10n.yesCancel,
      destructive: true,
    );
    if (!confirm) return;

    _poll?.cancel();
    setState(() => _busy = true);
    try {
      await ref.read(partnersProvider.notifier).rejectInvite(inviteId);
      if (mounted) {
        setState(() {
          _pendingInviteId = null;
          _pendingPartnerName = null;
        });
        await _showMsg(context.l10n.requestCancelled);
      }
    } catch (e) {
      if (mounted) {
        _startPolling(inviteId);
        await _showMsg(friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() => confirmAndLogout(context, ref);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    final partnersAsync = ref.watch(partnersProvider);

    return PopScope(
      canPop: !_busy,
      child: Stack(
      children: [
        CupertinoPageScaffold(
          backgroundColor: context.c.background,
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context), vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Profil',
                          style: context.t.headlineLarge?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: context.c.text90,
                          ),
                        ),
                      ),
                      const _ThemeToggleButton(),
                      const SizedBox(width: 8),
                      TourAnchor(
                        target: TourTarget.ayarlar,
                        child: CupertinoButton(
                        minimumSize: SandikTouch.minSize,
                        padding: EdgeInsets.zero,
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                  adaptiveRoute<void>(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                ),
                        child: _ActionIcon(
                          icon: Icons.settings_outlined,
                          color: context.c.text90,
                          disabled: _busy,
                          semanticLabel: context.l10n.settingsTitle,
                        ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SandikLogoutButton(
                        onPressed: _logout,
                        disabled: _busy,
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: AbsorbPointer(
                    absorbing: _busy,
                    child: RefreshIndicator(
      color: context.c.amberText,
      onRefresh: () async {
        await ref.read(partnersProvider.notifier).refresh();
        unawaited(ref.read(allPartnerAssetsProvider.notifier).reload());
      },
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                          horizontal: SandikSpace.screenH(context), vertical: 4),
                      children: [
                        // Oturum çözülmeden bu ekran kurulmaz; null yalnızca
                        // çıkış anındaki son karede görülebilir.
                        if (user != null) _buildUserHeader(user),
                        const SizedBox(height: 20),
                        const _ProfilePremiumBanner(),
                        const SizedBox(height: 24),
                        // Yıllık özet afişi. Kendi kendini kapatır: bayrak,
                        // takvim penceresi (26 Aralık–10 Ocak) ve verinin
                        // anlamlı olması. Yılın 11 ayı hiç görünmez.
                        const RecapBanner(),
                        const _PendingRequestsSection(),
                        const SizedBox(height: 8),
                        SandikSectionHeader(title: context.l10n.partnerActionsUpper),
                        const SizedBox(height: 16),
                        _buildInviteSection(),
                        const SizedBox(height: 32),
                        SandikSectionHeader(title: context.l10n.myPartnersUpper),
                        const SizedBox(height: 16),
                        partnersAsync.when(
                          loading: () => const CustomLoadingView(),
                          error: (e, _) => SandikErrorView(error: e),
                          data: (partners) => partners.isEmpty
                              ? _buildEmptyPartners()
                              : Column(
                                  children: [
                                    ...partners
                                        .map((p) => _buildPartnerTile(p)),
                                    const SizedBox(height: 20),
                                    const LeaderboardHeroCard(),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_busy) ...[
          const ModalBarrier(
              dismissible: false, color: Color(0xCC000000)),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: context.c.surface1,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color: context.c.overlay),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomLoadingIndicator(size: 22),
                  const SizedBox(width: 16),
                  Text(
                    _submitting
                        ? 'Ortaklık isteği gönderiliyor...'
                        : _generating
                            ? 'Kod üretiliyor...'
                            : 'İşleniyor...',
                    style: context.t.titleMedium?.copyWith(
                        color: context.c.text90),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
      ),
    );
  }

  Widget _buildUserHeader(AppUser user) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: context.c.amberFill.withValues(alpha: 0.1),
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: context.c.amberText),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: context.t.headlineMedium?.copyWith(
                      color: context.c.text90),
                ),
                const SizedBox(height: 4),
                Text(user.email,
                    style:
                        context.t.titleMedium?.copyWith(color: context.c.text36)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteSection() {
    return Column(
      children: [
        // Kod üretme
        TourAnchor(
          target: TourTarget.davetKodu,
          child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: context.c.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.generateInviteCode,
                  style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text90)),
              const SizedBox(height: 8),
              Text(
                context.l10n.generateInviteCodeBody,
                style: context.t.bodyMedium?.copyWith(color: context.c.text36),
              ),
              const SizedBox(height: 20),
              if (_generatedCode != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _generatedCode!.split(':')[0],
                          style: context.t.numLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.c.amberText,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: SandikTouch.minSize,
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          final shortCode = _generatedCode!.split(':')[0];
                          final msg =
                              'Merhaba! Sandık portföy uygulamasında seninle ortak olmak istiyorum.\n\n'
                              'Ortak kodun: $shortCode\n\n'
                              'Uygulamayı aç → Profil → "Ortak Kodu Gir" bölümünden bu kodu gir.';
                          await Share.share(msg, subject: 'Sandık Ortak Daveti');
                          unawaited(AnalyticsService.instance.logPartnerInviteSent());
                        },
                        child: Icon(Icons.share_rounded,
                            color: context.c.amberText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              CupertinoButton(
                onPressed: _generating ? null : _generateCode,
                padding: EdgeInsets.zero,
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: _generating
                        ? context.c.amberFill.withValues(alpha: 0.05)
                        : context.c.amberFill.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _generating ? context.l10n.generatingEllipsis : context.l10n.generateCode,
                    style: context.t.titleMedium?.copyWith(
                        color: context.c.amberText, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
        const SizedBox(height: 16),
        // Kod girme
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: context.c.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.enterPartnerCode,
                  style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text90)),
              const SizedBox(height: 8),
              Text(
                // Örnek kod gerçek alfabeden seçilmeli: 0/1/I/O üretimde
                // kullanılmıyor, "ABCDE-12345" hiç üretilemeyecek bir
                // koddu ve kullanıcıyı yanıltıyordu.
                context.l10n.enterPartnerCodeBody,
                style: context.t.bodyMedium?.copyWith(color: context.c.text36),
              ),
              const SizedBox(height: 16),
              if (_pendingInviteId != null) ...[
                _buildWaitingCard(),
              ] else ...[
                TextField(
                  controller: _codeCtrl,
                  // Kilitliyken alan kapalı: kullanıcı boşuna yazıp
                  // yeni bir ret almasın.
                  enabled: _rateLimitRemaining == 0,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  // Ortaklık kodu sözlükte olmayan bir dizidir; otomatik
                  // düzeltme ve öneri girilen kodu bozar.
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  // Tireyi kullanıcıdan beklemek "geçersiz format"
                  // hatasının başlıca sebebiydi; artık otomatik eklenir
                  // ve alfabe dışı karakterler süzülür.
                  inputFormatters: [PartnerCodeInputFormatter()],
                  onSubmitted: (_) {
                    if (!_submitting) _submitCode();
                  },
                  style: TextStyle(color: context.c.text90),
                  decoration: context.inputDecoration('XXXXX-XXXXX'),
                ),
                // Kilitliyken kalan süre canlı gösterilir; diyalog
                // kapandıktan sonra da ne kadar bekleneceği görünür.
                if (_rateLimitRemaining > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Material ikon fontu paketleniyor; CupertinoIcons
                      // burada tofu (boş kutu) olarak render ediliyordu.
                      Icon(Icons.schedule_rounded,
                          size: 15, color: context.c.text36),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.l10n.tooManyAttempts(_rateLimitLabel),
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text36),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                CupertinoButton(
                  onPressed: (_submitting || _rateLimitRemaining > 0)
                      ? null
                      : _submitCode,
                  padding: EdgeInsets.zero,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: (_submitting || _rateLimitRemaining > 0)
                          ? context.c.gain.withValues(alpha: 0.05)
                          : context.c.gain.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _submitting
                          ? context.l10n.sendingEllipsis
                          : (_rateLimitRemaining > 0
                              ? context.l10n.waitFor(_rateLimitLabel)
                              : context.l10n.requestPartnership),
                      style: context.t.titleMedium?.copyWith(
                          color: _rateLimitRemaining > 0
                              ? context.c.text36
                              : context.c.gain,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.c.amberFill.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border:
            Border.all(color: context.c.amberFill.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CustomLoadingIndicator(size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.awaitingApproval(_pendingPartnerName ?? ''),
                  style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text90),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            onPressed: _cancelPending,
            // HIG 44pt — 13pt metin sıfır padding'de ~17pt hedef veriyordu.
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(context.l10n.cancelWord,
                style: context.t.bodyMedium?.copyWith(color: context.c.text36)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPartners() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
          color: context.c.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
      child: Column(
        children: [
          Icon(Icons.people_outline_rounded,
              size: 48, color: context.c.text36),
          const SizedBox(height: 16),
          Text(
            context.l10n.noPartnersYet,
            style: context.t.titleMedium?.copyWith(color: context.c.text36),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerTile(PartnerAccount p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.c.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: p.isActive
                ? context.c.gain.withValues(alpha: 0.1)
                : context.c.text36.withValues(alpha: 0.1),
            child: Text(
              p.user.displayName.isNotEmpty
                  ? p.user.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  color: p.isActive ? context.c.gain : context.c.text36,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.user.displayName,
                    style: context.t.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.c.text90)),
                Text(
                  p.isActive ? 'Görünür' : 'Gizlendi',
                  style: context.t.titleSmall?.copyWith(
                      color: p.isActive ? context.c.gain : context.c.text36),
                ),
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: SandikTouch.minSize,
            padding: EdgeInsets.zero,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await ref
                        .read(partnersProvider.notifier)
                        .toggleHidden(p.user.id, p.isActive);
                    if (mounted) setState(() => _busy = false);
                  },
            child: _ActionIcon(
              icon: p.isActive
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: p.isActive ? context.c.text58 : context.c.gain,
              disabled: _busy,
              semanticLabel: p.isActive ? 'Ortağı gizle' : 'Ortağı göster',
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            minimumSize: SandikTouch.minSize,
            padding: EdgeInsets.zero,
            onPressed: _busy
                ? null
                : () => _confirmRemove(p.user.id, p.user.displayName),
            child: _ActionIcon(
              icon: Icons.delete_outline_rounded,
              color: context.c.loss,
              disabled: _busy,
              semanticLabel: context.l10n.removePartnerSemantics,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(String partnerId, String name) async {
    final confirm = await showSandikConfirm(
      context: context,
      title: context.l10n.removePartnerTitle,
      message: context.l10n.removePartnerBody(name),
      confirmLabel: context.l10n.removeWord,
      destructive: true,
    );
    if (confirm && mounted) {
      setState(() => _busy = true);
      await ref.read(partnersProvider.notifier).removePartner(partnerId);
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ── Bekleyen onay istekleri (kod sahibine gösterilir) ─────────────────────────

class _PendingRequestsSection extends ConsumerStatefulWidget {
  // `userId` parametresi KALDIRILDI: liste artık `pendingInvitesProvider`'dan
  // geliyor ve o kullanıcıyı `authProvider`'dan okuyor. Parametre kalsaydı
  // iki kaynak oluşur, çıkış/giriş sonrası biri eskiyebilirdi.
  const _PendingRequestsSection();

  @override
  ConsumerState<_PendingRequestsSection> createState() =>
      _PendingRequestsSectionState();
}

class _PendingRequestsSectionState
    extends ConsumerState<_PendingRequestsSection> {
  // Liste `pendingInvitesProvider`'da — bu bölümün KENDİ kopyası YOK.
  //
  // **Ölçülen arıza (kullanıcı bildirimi, 2026-09-16):** kullanıcı bildirimden
  // gelen isteği onaylıyor, geri dönünce istek BURADA duruyordu; ikinci kez
  // basınca "Bu davet zaten yanıtlanmış" hatası alıyordu. Bildirim yolu
  // `PartnershipRequestsScreen`'i bu ekranın ÜSTÜNE push ediyor; orada onay
  // verilince burası haberdar olmuyordu (`initState` geri dönüşte yeniden
  // çalışmaz, `ForegroundPoller` yalnızca uygulama arka plandan dönünce
  // tetikleniyor). Gerekçenin tamamı `pendingInvitesProvider`'da.
  //
  // Poller güvenlik ağı olarak kalıyor: aynı anda karşı taraf yeni bir istek
  // gönderirse ekranı açık tutan kullanıcı 20 sn içinde görür.
  late final ForegroundPoller _poller =
      ForegroundPoller(interval: const Duration(seconds: 20), onTick: _load);

  @override
  void initState() {
    super.initState();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _load() => ref.read(pendingInvitesProvider.notifier).refresh();

  Future<void> _showMsg(String msg, {bool isError = false}) =>
      _showPartnerMsg(context, msg, isError: isError);

  Future<void> _accept(Map<String, dynamic> invite) async {
    final kabulEdildi = context.l10n.partnershipAccepted;
    final inviteId = invite['id'] as String;
    try {
      await ref.read(partnersProvider.notifier).acceptInvite(inviteId);
      // Sunucu turunu beklemeden düşür — o aralıkta kart basılabilir kalıyordu.
      ref.read(pendingInvitesProvider.notifier).kaldir(inviteId);
      unawaited(ref.read(allPartnerAssetsProvider.notifier).reload());
      await _load();
      await _showMsg(kabulEdildi);
    } catch (e) {
      await _showMsg(friendlyError(e), isError: true);
    }
  }

  Future<void> _reject(Map<String, dynamic> invite) async {
    final inviteId = invite['id'] as String;
    try {
      await ref.read(partnersProvider.notifier).rejectInvite(inviteId);
      ref.read(pendingInvitesProvider.notifier).kaldir(inviteId);
      await _load();
    } catch (e) {
      await _showMsg(friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingInvites =
        ref.watch(pendingInvitesProvider).valueOrNull ?? const [];
    if (pendingInvites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SandikSectionHeader(title: context.l10n.pendingRequestsUpper),
        const SizedBox(height: 12),
        ...pendingInvites.map((invite) => _PendingInviteTile(
              invite: invite,
              onAccept: () => _accept(invite),
              onReject: () => _reject(invite),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PendingInviteTile extends StatefulWidget {
  final Map<String, dynamic> invite;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _PendingInviteTile(
      {required this.invite, required this.onAccept, required this.onReject});

  @override
  State<_PendingInviteTile> createState() => _PendingInviteTileState();
}

class _PendingInviteTileState extends State<_PendingInviteTile> {
  String _requesterName = '...';

  @override
  void initState() {
    super.initState();
    final requesterName =
        ((widget.invite['requester_name'] as String?) ?? '').trim();
    if (requesterName.isNotEmpty) {
      _requesterName = requesterName;
      return;
    }
    _loadRequesterName();
  }

  Future<void> _loadRequesterName() async {
    final toUserId = widget.invite['to_user_id'] as String?;
    if (toUserId == null) return;
    AppUser? profile;
    try {
      profile = await SupabaseService.instance.getProfile(toUserId);
    } catch (_) {
      profile = null;
    }
    if (mounted) {
      setState(() => _requesterName = profile?.displayName ?? 'Kullanıcı');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.c.amberFill.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border:
            Border.all(color: context.c.amberFill.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: context.c.amberFill.withValues(alpha: 0.15),
            child: Text(
              _requesterName.isNotEmpty ? _requesterName[0].toUpperCase() : '?',
              style: TextStyle(
                  color: context.c.amberText, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_requesterName,
                    style: context.t.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.c.text90)),
                Text(context.l10n.wantsToPartner,
                    style:
                        context.t.titleSmall?.copyWith(color: context.c.text36)),
              ],
            ),
          ),
          // HIG: dokunma hedefi min 44×44pt. İkon 22pt kalır, tıklanabilir
          // alan görünmez şekilde 44pt'ye genişletilir.
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: widget.onReject,
            child: Semantics(
              button: true,
              label: context.l10n.rejectRequest,
              child:
                  Icon(Icons.close_rounded, color: context.c.loss, size: 22),
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: widget.onAccept,
            child: Semantics(
              button: true,
              label: context.l10n.acceptRequest,
              child:
                  Icon(Icons.check_rounded, color: context.c.gain, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}


class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool disabled;
  final String semanticLabel;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.disabled,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = disabled ? color.withValues(alpha: 0.35) : color;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: iconColor.withValues(alpha: 0.18)),
        ),
        child: Center(child: Icon(icon, color: iconColor, size: 20)),
      ),
    );
  }
}

/// Tema modu hızlı geçişi — Profil başlığında.
///
/// **Neden burada:** iOS HIG ve Material 3, görünüm ayarını hesap/ayarlar
/// bölgesine koyar. Ana sayfa başlığına eklemek düşünüldü ama orada zaten
/// dört aksiyon var ve satır 17px taşıyordu (bkz. `home_screen` yorumu);
/// beşincisi yerleşimi kırardı. Profil başlığı hem boş hem de kullanıcının
/// "kendi tercihlerim" diye aradığı yer.
///
/// Ayarlar'daki üçlü seçici (`_ThemeModePicker`) kalır — bu onun kısayolu.
/// Tek dokunuşla **açık ↔ koyu** arasında gider; "sistem" bilinçli bir
/// tercih olduğu için yalnızca Ayarlar'dan seçilir. Kullanıcı sistemdeyken
/// dokunursa, o an ekranda ne görüyorsa onun tersine geçer.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tercih değişince yeniden çizilmek için izlenir; kararı `context`
    // verir çünkü `system` modda ekrandaki gerçek parlaklık cihazdan gelir.
    ref.watch(themeModeProvider);
    final showingLight = context.isLight;
    final next = showingLight ? ThemeMode.dark : ThemeMode.light;

    return SandikTappable(
      semanticLabel:
          showingLight ? context.l10n.switchToDark : context.l10n.switchToLight,
      onTap: () => ref.read(themeModeProvider.notifier).set(next),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.c.text90.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.text90.withValues(alpha: 0.18)),
        ),
        child: Center(
          // Gösterilen ikon HEDEFI anlatır: açık temadayken ay ikonu
          // "koyuya geç" der. Mevcut durumu göstermek daha yaygın bir
          // hata — kullanıcı ikona bakıp ne olacağını bilmek ister.
          child: AnimatedSwitcher(
            duration: SandikMotion.stateOf(context),
            switchInCurve: SandikMotion.enter,
            switchOutCurve: SandikMotion.enter,
            child: Icon(
              showingLight
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              key: ValueKey(showingLight),
              color: context.c.text90,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Premium banner ────────────────────────────────────────────────────────

class _ProfilePremiumBanner extends ConsumerWidget {
  const _ProfilePremiumBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Paywall master switch kapalıysa banner hiç gösterilmez.
    if (!ref.watch(paywallVisibleProvider)) return const SizedBox.shrink();
    final premium = ref.watch(effectivePremiumProvider);
    if (premium) return const _PremiumActiveBadge();
    return GestureDetector(
      onTap: () {
        AnalyticsService.instance
            .logPremiumGateShown(feature: 'profile_banner');
        PaywallScreen.show(context, source: 'profile_banner');
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              context.c.amberFill.withValues(alpha: 0.20),
              context.c.gold.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.amberFill.withValues(alpha: 0.40)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.c.amberFill.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(SandikRadius.md),
              ),
              child: Icon(Icons.workspace_premium_rounded,
                  color: context.c.amberText, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.sandikPremium,
                      style: context.t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: context.c.text90)),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.premiumPitch,
                    style: context.t.bodySmall?.copyWith(
                        color: context.c.text58,
                        height: 1.35),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: context.c.amberText),
          ],
        ),
      ),
    );
  }
}

class _PremiumActiveBadge extends StatelessWidget {
  const _PremiumActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.c.gain.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.gain.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.c.gain.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: Icon(Icons.check_circle_outline_rounded,
                color: context.c.gain, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.premiumActive,
                    style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.c.text90)),
                const SizedBox(height: 2),
                Text(context.l10n.premiumActiveBody,
                    style: context.t.bodySmall?.copyWith(color: context.c.text58)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

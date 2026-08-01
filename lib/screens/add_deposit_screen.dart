import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';
import '../services/deposit_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'paywall_screen.dart';

/// Vadeli mevduat ekleme ekranı. Sıradan Asset formundan ayrı — çünkü
/// mevduatın "quantity + purchasePrice" mantığı yok; anapara + faiz + vade
/// var. Kaydedildiğinde Asset olarak yazılır (subCategory serileştirilmiş).
class AddDepositScreen extends ConsumerStatefulWidget {
  const AddDepositScreen({super.key});

  @override
  ConsumerState<AddDepositScreen> createState() => _AddDepositScreenState();
}

class _AddDepositScreenState extends ConsumerState<AddDepositScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtl = TextEditingController();
  final _principalCtl = TextEditingController();
  final _rateCtl = TextEditingController();
  final _taxCtl = TextEditingController();

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 90));
  DepositInterestType _interestType = DepositInterestType.compound;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _principalCtl.dispose();
    _rateCtl.dispose();
    _taxCtl.dispose();
    super.dispose();
  }

  int get _termDays => _end.difference(_start).inDays;

  // Canlı önizleme: kullanıcı formu doldururken vade sonu net getiri.
  double? get _previewMaturityNet {
    final p = double.tryParse(_principalCtl.text.replaceAll(',', '.'));
    final r = double.tryParse(_rateCtl.text.replaceAll(',', '.'));
    if (p == null || r == null || p <= 0 || r <= 0 || _termDays <= 0) {
      return null;
    }
    final tax = double.tryParse(_taxCtl.text.replaceAll(',', '.')) ??
        DepositService.defaultTaxRate;
    final terms = DepositTerms(
      start: _start,
      end: _end,
      annualRatePct: r,
      interestType: _interestType,
      taxRatePct: tax,
      taxWasProvided: _taxCtl.text.trim().isNotEmpty,
    );
    return p * DepositService.maturityUnitValue(terms);
  }

  Future<void> _pickDate(bool start) async {
    final initial = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Sandik.amber,
            surface: Sandik.surface1,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(days: 30));
        }
      } else {
        if (picked.isAfter(_start)) _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_termDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vade sonu, başlangıç tarihinden sonra olmalı')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final principal = double.parse(_principalCtl.text.replaceAll(',', '.'));
      final rate = double.parse(_rateCtl.text.replaceAll(',', '.'));
      final taxText = _taxCtl.text.trim();
      final tax = taxText.isEmpty
          ? DepositService.defaultTaxRate
          : double.parse(taxText.replaceAll(',', '.'));

      final sub = DepositService.encode(
        start: _start,
        end: _end,
        annualRatePct: rate,
        interestType: _interestType,
        taxRatePct: tax,
      );

      final terms = DepositTerms(
        start: _start,
        end: _end,
        annualRatePct: rate,
        interestType: _interestType,
        taxRatePct: tax,
        taxWasProvided: taxText.isNotEmpty,
      );
      final currentUnit = DepositService.currentUnitValue(terms);

      final name = _nameCtl.text.trim().isEmpty
          ? 'Vadeli Mevduat'
          : _nameCtl.text.trim();

      await ref.read(portfolioProvider.notifier).addAsset(
            name: name,
            ticker: '',
            type: AssetType.mevduat,
            quantity: principal, // anapara
            purchasePrice: 1.0, // birim = 1 TL
            currency: 'TRY',
            notes: '',
            isManualPrice: true,
            subCategory: sub,
            unitType: 'try',
            addedDate: _start,
            initialCurrentPrice: currentUnit,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AssetLimitExceededException {
      if (!mounted) return;
      final upgraded = await PaywallScreen.show(
        context,
        source: 'asset_limit_deposit',
      );
      if (upgraded == true && mounted) {
        // Kullanıcı premium'a geçti — kaydetmeyi tekrar dene
        _save();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final dateFmt = DateFormat('dd.MM.yyyy', 'tr_TR');
    final maturityNet = _previewMaturityNet;

    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Sandik.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Vadeli Mevduat',
          style: context.t.headlineMedium?.copyWith(
            color: Colors.white,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // ── Ad ────────────────────────────────────────────────────────────
            _label('Hesap Adı (opsiyonel)'),
            _textField(
              controller: _nameCtl,
              hint: 'ör. Garanti 6 ay TL',
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 18),

            // ── Anapara ───────────────────────────────────────────────────────
            _label('Anapara (₺)'),
            _textField(
              controller: _principalCtl,
              hint: 'ör. 50000',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (n == null || n <= 0) return 'Geçerli bir anapara girin';
                return null;
              },
            ),
            const SizedBox(height: 18),

            // ── Yıllık faiz ───────────────────────────────────────────────────
            _label('Yıllık Faiz Oranı (%)'),
            _textField(
              controller: _rateCtl,
              hint: 'ör. 45.5',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (n == null || n <= 0 || n > 500) {
                  return '0 ile 500 arası bir oran girin';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),

            // ── Faiz türü ─────────────────────────────────────────────────────
            _label('Faiz Türü'),
            _InterestTypeSelector(
              value: _interestType,
              onChanged: (v) => setState(() => _interestType = v),
            ),
            const SizedBox(height: 18),

            // ── Tarihler ──────────────────────────────────────────────────────
            _label('Vade Başlangıç'),
            _DateRow(
              text: dateFmt.format(_start),
              onTap: () => _pickDate(true),
            ),
            const SizedBox(height: 12),
            _label('Vade Sonu'),
            _DateRow(
              text: dateFmt.format(_end),
              onTap: () => _pickDate(false),
            ),
            const SizedBox(height: 8),
            if (_termDays > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Vade süresi: $_termDays gün',
                  style: context.t.titleSmall?.copyWith(
                    color: Sandik.text58,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 18),

            // ── Stopaj ────────────────────────────────────────────────────────
            _label('Stopaj Oranı (%)  —  opsiyonel'),
            _textField(
              controller: _taxCtl,
              hint: 'Boş bırakırsan ${fmtPct(DepositService.defaultTaxRate, digits: 0)} kullanılır',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                final n = double.tryParse(v!.replaceAll(',', '.'));
                if (n == null || n < 0 || n > 100) {
                  return '0 ile 100 arası bir oran girin';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            _InfoBox(
              text:
                  'TR mevduat stopajı vadeye göre değişir (6+ ay: %10, 1+ yıl: %5, kısa vade: %15). '
                  'Kesin oran için banka dekontunuzu kontrol edin. Belirtmezseniz '
                  '${fmtPct(DepositService.defaultTaxRate, digits: 0)} varsayılan kullanılır.',
            ),
            const SizedBox(height: 20),

            // ── Önizleme ──────────────────────────────────────────────────────
            if (maturityNet != null)
              _PreviewCard(
                principal:
                    double.parse(_principalCtl.text.replaceAll(',', '.')),
                maturityNet: maturityNet,
                termDays: _termDays,
                money: money,
              ),
            const SizedBox(height: 24),

            // ── Kaydet ────────────────────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Sandik.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        'Mevduatı Kaydet',
                        style: context.t.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          s,
          style: context.t.titleSmall?.copyWith(
            color: Sandik.text58,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required TextInputType keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: context.t.numMedium.copyWith(
        fontSize: 15,
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: context.t.titleMedium?.copyWith(
          color: Sandik.text36,
        ),
        filled: true,
        fillColor: Sandik.surface1,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md),
          borderSide: BorderSide(color: AssetType.mevduat.color, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}

class _InterestTypeSelector extends StatelessWidget {
  final DepositInterestType value;
  final ValueChanged<DepositInterestType> onChanged;
  const _InterestTypeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        children: [
          for (final t in DepositInterestType.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: value == t
                        ? AssetType.mevduat.color.withValues(alpha: 0.20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                      color: value == t
                          ? AssetType.mevduat.color.withValues(alpha: 0.55)
                          : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      t.label,
                      style: context.t.titleSmall?.copyWith(
                        fontWeight:
                            value == t ? FontWeight.w800 : FontWeight.w600,
                        color: value == t
                            ? AssetType.mevduat.color
                            : Sandik.text58,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _DateRow({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: Sandik.text58),
            const SizedBox(width: 10),
            Text(
              text,
              style: context.t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Sandik.text58),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Sandik.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: Sandik.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Sandik.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: context.t.bodySmall?.copyWith(
                color: Sandik.amber,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final double principal;
  final double maturityNet;
  final int termDays;
  final NumberFormat money;

  const _PreviewCard({
    required this.principal,
    required this.maturityNet,
    required this.termDays,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final gain = maturityNet - principal;
    final pct = principal > 0 ? (gain / principal) * 100 : 0.0;
    final good = gain >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AssetType.mevduat.color.withValues(alpha: 0.15),
            AssetType.mevduat.color.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
            color: AssetType.mevduat.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_rounded,
                  color: AssetType.mevduat.color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Vade Sonu Öngörüsü',
                style: context.t.numSmall.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AssetType.mevduat.color,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _row(context, 'Anapara', money.format(principal)),
          _row(context, 'Vade Sonu (Net)', money.format(maturityNet),
              bold: true),
          _row(
            context,
            'Net Getiri',
            '${good ? '+' : ''}${money.format(gain)}  '
                '(${fmtPct(pct, digits: 2, showSign: good)})',
            color: good ? Sandik.gain : Sandik.loss,
            bold: true,
          ),
          const SizedBox(height: 6),
          Text(
            'Stopaj ve faiz türü hesaba dahil edilmiştir.',
            style: context.t.labelMedium?.copyWith(
              letterSpacing: 0,
              color: Sandik.text58,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String k, String v,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            k,
            style: context.t.titleSmall?.copyWith(
              color: Sandik.text58,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            v,
            style: context.t.numSmall.copyWith(
              color: color ?? Colors.white,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

# Implementação de Sinais Técnicos de Compra/Venda

## 📊 Visão Geral
Foi implementado um sistema completo de análise técnica com sinais de compra/venda na tela de análise detalhada do portfólio. O sistema utiliza os **5 indicadores técnicos mais populares** da análise técnica tradicional.

## 🎯 Funcionalidades Principais

### 1. **Cinco Indicadores Técnicos**
O sistema calcula e analisa:
- **RSI (Relative Strength Index)**: Identifica condições de sobrevenda (<30) e sobrecompra (>70)
- **MACD (Moving Average Convergence Divergence)**: Analisa o cruzamento de médias móveis
- **Bandas de Bollinger**: Detecta quando o preço está fora das bandas de volatilidade
- **SMA/EMA (Simple/Exponential Moving Average)**: Verifica a posição do preço em relação às médias
- **Oscilador Estocástico**: Identifica níveis de sobrecompra (>80) e sobrevenda (<20)

### 2. **Sinais Gerados**
Para cada categoria de ativo (Ações, Fundos, Moedas, Ouro, Commodities), o sistema gera:
- **Sinal de Compra** (Trending Up): Quando indicadores indicam condições bullish
- **Sinal de Venda** (Trending Down): Quando indicadores indicam condições bearish
- **Sinal Neutral** (Trending Flat): Quando não há consenso entre indicadores

### 3. **Informações Exibidas**
A interface mostra:
- **Sinal do Portfólio Total**: Agregação de todos os sinais de todas as categorias
- **Valor Total do Portfólio**: Em reais (₺)
- **Contagem de Sinais**: Total de sinais de compra, venda e neutralidade
- **Análise por Categoria**: Para cada tipo de ativo:
  - Sinal geral da categoria
  - Nível de confiança (0-100%)
  - Valor total de ativos na categoria
  - Número de indicadores analisados
  - Contagem detalhada de sinais por indicador

## 📁 Arquivos Criados/Modificados

### Novos Arquivos:
1. **`lib/models/technical_signal.dart`**
   - Modelos de dados para sinais técnicos
   - Classes: `TechnicalIndicator`, `CategorySignal`, `PortfolioSignalAnalysis`
   - Enum: `SignalType` (buy, sell, neutral)

2. **`lib/services/technical_analysis_service.dart`**
   - Serviço com algoritmos de cálculo dos indicadores
   - Métodos principais:
     - `calculateRSI()`: RSI com período 14
     - `calculateMACD()`: MACD com EMA 12/26 e sinal 9
     - `calculateBollingerBands()`: Bandas com período 20 e desvio padrão 2
     - `calculateStochastic()`: Oscilador Estocástico com período 14
     - `calculateSMA()`: Média Móvel Simples
     - `analyzeAsset()`: Analisa um ativo individualmente
     - `generatePortfolioSignals()`: Gera análise completa do portfólio

### Arquivos Modificados:
1. **`lib/screens/portfolio_detail_screen.dart`**
   - Adicionados imports: `technical_signal.dart` e `technical_analysis_service.dart`
   - Novo método: `_buildSignalsSection()` - Widget principal da seção de sinais
   - Novo método: `_buildCategorySignalTile()` - Card individual por categoria
   - Novo método: `_signalBadge()` - Componente visual de sinais agregados
   - Novo método: `_indicatorBadge()` - Componente visual de contagem de indicadores
   - Seção adicionada ao ListView da tela (após "Ortaklar")

## 🎨 UI/UX

### Layout da Seção de Sinais:
```
┌─────────────────────────────────────┐
│  SINAIS TÉCNICOS                    │
├─────────────────────────────────────┤
│ 📈 Sinal de Compra                  │
│ Portfólio Total: ₺ 123.456,78       │
│ [Compra: 8] [Venda: 2] [Neutral: 5]│
├─────────────────────────────────────┤
│ 📈 Ações (Confiança: 80%)           │
│ Total: ₺ 50.000,00 | 5 indicadores │
│ [Compra: 3] [Venda: 1] [Neutral: 1]│
├─────────────────────────────────────┤
│ 📊 Fundos (Confiança: 60%)          │
│ Total: ₺ 35.000,00 | 5 indicadores │
│ [Compra: 2] [Venda: 1] [Neutral: 2]│
└─────────────────────────────────────┘
```

### Cores de Indicadores:
- **Compra**: Verde (#10B981)
- **Venda**: Vermelho (#EF4444)
- **Neutral**: Cinza (Sandik.text36)

## 📊 Algoritmos Técnicos

### RSI (Relative Strength Index)
- Período: 14
- Cálculo: Razão entre ganhos e perdas médios
- Sinais:
  - Compra: RSI < 30 (sobrevenda)
  - Venda: RSI > 70 (sobrecompra)
  - Neutral: 30 ≤ RSI ≤ 70

### MACD
- EMA rápida: 12 períodos
- EMA lenta: 26 períodos
- Linha de sinal: EMA 9 da MACD
- Cálculo: MACD = EMA12 - EMA26
- Sinais:
  - Compra: MACD > linha de sinal
  - Venda: MACD < linha de sinal
  - Neutral: MACD ≈ linha de sinal

### Bandas de Bollinger
- Período: 20
- Desvios padrão: 2
- Cálculo: SMA ± (2 × StdDev)
- Sinais:
  - Compra: Preço < banda inferior
  - Venda: Preço > banda superior
  - Neutral: Preço dentro das bandas

### SMA/EMA
- SMA: Período 20
- EMA: Período 50
- Sinais:
  - Compra: Preço > SMA20 E SMA20 > EMA50
  - Venda: Preço < SMA20 E SMA20 < EMA50
  - Neutral: Outros cenários

### Oscilador Estocástico
- Período: 14
- Cálculo: ((Preço - Mín14) / (Máx14 - Mín14)) × 100
- Sinais:
  - Compra: Oscilador < 20 (sobrevenda)
  - Venda: Oscilador > 80 (sobrecompra)
  - Neutral: 20 ≤ Oscilador ≤ 80

## 🔄 Fluxo de Dados

1. **Tela de Análise Detalhada** carrega a lista de ativos
2. **TechnicalAnalysisService** calcula indicadores para cada ativo
3. **Sinais são agregados** por categoria de ativo
4. **Sinal geral do portfólio** é calculado a partir de todos os sinais
5. **Interface exibe** a análise completa com cores e ícones

## 🚀 Como Usar

1. Acesse a tela "Detalhı Portföy Analizi"
2. Rolle para baixo até a seção "SINAIS TÉCNICOS"
3. Observe:
   - Sinal geral do portfólio (compra/venda/neutral)
   - Valor total do portfólio
   - Contagem de sinais por tipo
   - Análise detalhada por categoria
   - Confiança de cada sinal

## 📈 Casos de Uso

- **Investidores**: Verificar rapidamente o consenso técnico antes de fazer investimentos
- **Analistas**: Comparar sinais entre diferentes categorias de ativos
- **Rastreamento**: Monitorar mudanças nos sinais técnicos ao longo do tempo

## ⚙️ Detalhes Técnicos

### Performance
- Cálculos otimizados usando métodos eficientes
- Sem operações síncronas pesadas
- Interface responsiva mesmo com muitos ativos

### Precisão
- Usa histórico simulado de 100 dias
- Algoritmos baseados em interpretações padrão da indústria
- Confiança calculada como % de indicadores em consenso

## 🔮 Possíveis Melhorias Futuras

1. **Dados em Tempo Real**: Conectar com API para histórico real de preços
2. **Alertas**: Notificar quando sinais mudam
3. **Backtesting**: Testar efetividade dos sinais historicamente
4. **Customização**: Permitir ajustar períodos dos indicadores
5. **Exportação**: Exportar análises em PDF/Excel
6. **Histórico**: Guardar histórico de sinais ao longo do tempo

## ✅ Status de Implementação

- ✅ Modelo de dados de sinais
- ✅ Cálculo de 5 indicadores técnicos
- ✅ Análise por categoria
- ✅ Interface visual completa
- ✅ Integração na tela de análise
- ✅ Build Android bem-sucedido
- ✅ Sem erros de compilação

---

**Data**: 21 de Abril de 2026  
**Status**: Pronto para uso e testes

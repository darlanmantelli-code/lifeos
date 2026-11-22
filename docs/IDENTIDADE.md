# Identidade visual do livo

*Vida inteligente. Sua vida mais simples.*

A identidade nasce do logo: uma **barra azul** inclinada e uma **folha menta** que cresce ao lado dela. A barra é a
estrutura (organização, disciplina); a folha é o crescimento (saúde, patrimônio, hábitos).

## Logo

- Marca vetorial desenhada em código (`Livo/Core/LivoMark.swift`), com geometria ajustada ao arquivo de referência
  (`LivoMarkGeometry.swift`, gerada a partir do logo). Nítida em qualquer tamanho e nos dois modos.
- Variante escura: azul e menta mais claros, para manter contraste sobre o azul profundo.
- Use `LivoMark` (marca), `Wordmark` (texto "livo" em SF Rounded Heavy) e `BrandLockup` (os dois juntos).
- Área livre mínima: metade da largura da barra em todos os lados. Não gire, não distorça, não troque as cores.
- Ícone do app: marca sobre branco gelo (claro) ou azul profundo (escuro); `Livo/Resources/Assets.xcassets/AppIcon.appiconset`.

## Paleta

| Papel | Claro | Escuro | Origem |
|---|---|---|---|
| Tinta / títulos (`lifeInk`) | `#14283B` | `#F3F6FA` | azul profundo |
| Fundo (`lifeCanvas`) | `#F6F8FA` | `#0E1C2B` | branco gelo / azul profundo |
| Cartões (`lifeSurface`) | `#FFFFFF` | `#172B40` | — / entre profundo e grafite |
| Linhas finas (`lifeHairline`) | `#E2E8EF` | `#26364A` | azul grafite no escuro |
| Ação (`lifeAccent`) | `#0462D0` | `#6BA9FF` | azul do logo |
| Crescimento (`lifeProgress`) | `#2BD08F` | `#5BE8B0` | menta do logo |
| Menta suave (`lifeMintSoft`) | `#A4E8DB` | `#1D4D4A` | verde menta |
| Receita (texto) (`lifeIncome`) | `#087F55` | `#5BE8B0` | menta escurecida p/ contraste |
| Despesa (`lifeExpense`) | `#D92D3A` | `#FF7A80` | — |

**A cor tem significado, não é enfeite:** azul = o que você pode tocar (botões, seleção, links);
menta = crescimento (progresso de metas, itens concluídos, receitas); tinta = texto.

## Tipografia

SF Rounded em todo o app (`.fontDesign(.rounded)`), que ecoa as letras arredondadas do logo. Títulos grandes em *Heavy*,
corpo em peso normal, valores em dígitos tabulares (`monospacedDigit`). Os títulos da barra de navegação são configurados
em `BrandAppearance` porque o UIKit não lê o `fontDesign` do SwiftUI. Tudo respeita Dynamic Type.

## Elementos

- **Cartão principal** (`.heroCard()`): o único elemento "barulhento", usado no saldo do painel. Degradê azul do logo com a
  marca em marca-d'água. Todo o resto é calmo: cartões brancos (`.card()`) com linha fina e sombra suave.
- **Fundo** (`.brandScreen()`): todas as telas usam o branco gelo / azul profundo da marca em vez do cinza do sistema.
- **Tela de abertura**: fundo da marca com o logo centralizado (claro e escuro).
- **Widget**: azul do logo com a marca em marca-d'água; o saldo fica oculto quando o iPhone está bloqueado.

## Voz

Frases curtas, verbos simples, sem jargão financeiro. "Sua vida mais simples" é o compromisso: cada tela deve reduzir
trabalho, não criar mais um. A frase da marca fica em `Brand` (`DesignSystem.swift`); mudar lá muda o app todo.

## Observações

- A referência traz "Vida inteligente." e "Sua vida mais simples."; antes o slogan combinado era "sua vida mais
  inteligente". Para voltar a ele, altere só `Brand.headline`/`Brand.tagline`.
- Linhas de lista (`List`) usam o fundo de linha do sistema (branco no claro, cinza escuro no escuro); o SwiftUI não
  permite trocar isso globalmente, só por linha.

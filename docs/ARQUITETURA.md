# livo — Arquitetura e plano

*sua vida mais inteligente*

## Arquitetura

| Camada | Escolha |
|---|---|
| App | Swift 6 + SwiftUI, iOS 17+ |
| Projeto | XcodeGen (`project.yml`) — `.xcodeproj` é gerado, não versionado |
| Padrão | MVVM: View → ViewModel `@Observable` → Service (um por módulo) → SwiftData |
| Persistência | SwiftData local, proteção de arquivo `complete` |
| Dinheiro | `Int64` em centavos (`Core/Money.swift`), nunca `Double` |
| Sync (futuro) | CloudKit — modelos com valores padrão e sem `@Attribute(.unique)` desde já |
| IA | App ↔ backend FastAPI ↔ API do modelo. Chave só no servidor |
| Segurança | Face ID (LocalAuthentication), Keychain para token do backend |

**LIFE AI**: o backend repassa a mensagem ao modelo com as ferramentas declaradas.
Ferramentas são executadas **no aparelho** contra o SwiftData; só o resultado sai.
Ferramentas de escrita/exclusão exigem confirmação na UI e são registradas em `AIActionLog`.

**Modo demonstração**: container em memória separado, faixa fixa "Modo demonstração".

## Mapa de telas

```
TabView
├─ Início ── saudação, Dia/Semana/Mês, widgets reorganizáveis, busca global
│            └─ Menu geral: Compras · Saúde · Estudos* · Automações* · Configurações · Privacidade
├─ Finanças ─ Visão geral · Contas/Cartões · Lançamentos · Orçamentos · Patrimônio*
├─ Adicionar  (sheet) → Despesa · Receita · Tarefa · Hábito ✓ · Item de compra · Saúde
├─ Rotina ─── Hoje · Metas → etapas · Hábitos → calendário/sequência · Agenda*
└─ IA ──────── Chat LIFE AI · Histórico de ações
* fora do MVP
```

## Modelo de dados (MVP)

- **Account**: nome, tipo (corrente/poupança/carteira/cartão), saldoInicialCents, limiteCents?, diaFechamento?, diaVencimento?, arquivada
- **Category**: nome, tipo (receita/despesa), ícone, cor, pai?
- **Transaction**: data, valorCents, tipo (receita/despesa/transferência), conta, contaDestino?, categoria?, nota, fixa, grupoParcelaID?, parcela X/Y, recorrência?, origem (manual/importação/IA)
- **Budget**: categoria, mês `yyyy-MM`, limiteCents
- **Goal** / **GoalStep**
- **Habit** / **HabitCheckIn**
- **TaskItem** (evita colisão com `Task`)
- **ShoppingList** / **ShoppingItem** — preço com origem + data de observação
- **HealthEntry**: tipo, valor, unidade, data, origem (manual/HealthKit)
- **AIActionLog**

Saldos, sequências e progresso são calculados, não armazenados. Layout do dashboard em `@AppStorage`.

## Etapas (cada uma: CI verde)

0. Base: projeto, CI macOS, design system ✅
1. Finanças manual: contas, categorias, lançamentos (único/parcelado/recorrente), orçamento ✅
2. Rotina: tarefas, hábitos (sequência, calendário), metas com etapas ✅
3. Compras (listas, desejos, histórico de preço) e Saúde manual + gráficos ✅
4. Painel com widgets reorganizáveis (Dia/Semana/Mês), alertas, busca global, Adicionar ✅
5. livo IA: backend FastAPI + ferramentas no aparelho + confirmação + histórico ✅
6. Privacidade: Face ID, exportar/restaurar/apagar, modo demonstração ✅
7. TestFlight (exige Apple Developer)

Pós-MVP: HealthKit, EventKit/Reminders, App Intents, widgets, CSV/OFX, automações
(`BGAppRefreshTask` + notificações locais), estudos/Pomodoro, CloudKit, Open Finance (provedor autorizado), comparação de preços.

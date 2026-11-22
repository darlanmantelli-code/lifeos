# livo web

Versão web do livo: PWA instalável, **local no navegador** (IndexedDB), na mesma identidade visual do app iOS.
*Vida inteligente. Sua vida mais simples.*

## O que tem

Início (resumo, alertas, tarefas, hábitos, metas, saúde, compras) · Busca global · Estudos (revisões espaçadas e Pomodoro) · Finanças (lançamentos únicos, parcelados e recorrentes,
contas e cartões, categorias, orçamentos, projeção de saldo, gastos incomuns, importação OFX/CSV) · Rotina (tarefas,
hábitos com sequência, metas com etapas) · Compras (listas, desejos, histórico de preços informados por você) ·
Saúde (registros manuais, gráficos, metas diárias) · Configurações (tema, backup, apagar tudo, modo demonstração).

Ainda não há na web: assistente livo IA, automações, Siri/Atalhos, Apple Saúde e widgets
(esses dados, quando vêm de um backup do iPhone, são preservados ao exportar de volta).

## Dados e privacidade

- Tudo fica no IndexedDB do navegador (`livo`). Nada é enviado a servidor, e nenhuma conta bancária é acessada.
- O modo demonstração usa outro banco (`livo-demo`) com dados fictícios e uma faixa fixa; os dados reais não são tocados.
- **Backup compatível com o iPhone**: *Configurações › Exportar backup* gera o mesmo JSON do app iOS
  (`app: "livo"`, `versao: 1`, datas ISO 8601 sem milissegundos). Exporte em um lado e restaure no outro.
  Os testes (`src/data/data.test.ts`) conferem que o arquivo exportado traz todos os campos que o app iOS exige.
- Os comprovantes anexados no iPhone ficam só no aparelho e não entram no backup.

## Rodar

```
npm install
npm run dev       # http://localhost:5173
npm test          # vitest: lógica, backup e ações
npm run build     # typecheck + build estático em dist/
```

O build usa caminhos relativos e roteamento por `#`, então funciona em qualquer pasta ou subcaminho
(GitHub Pages, servidor próprio, NAS). Depois da primeira visita o app abre offline (service worker `public/sw.js`).

## Estrutura

```
src/lib        dinheiro (centavos) e datas (calendário local, semana começa no domingo)
src/domain     regras puras portadas do app iOS: finanças, rotina, saúde, compras, extratos
src/data       Dexie (IndexedDB), ações de escrita, backup, demo
src/pages      telas;  src/components  UI e gráficos SVG;  src/brand  logo vetorial
```

A lógica em `src/domain` tem os mesmos casos de teste do app (parcelas, saldo, fatura, sequências, projeção…),
para que web e iPhone calculem igual.

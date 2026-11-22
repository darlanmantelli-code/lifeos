# livo

*Vida inteligente. Sua vida mais simples.*

App iOS pessoal (SwiftUI, iOS 17+). Arquitetura e plano: [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## Build

Precisa de macOS com Xcode 16+.

```
brew install xcodegen
xcodegen generate
open Livo.xcodeproj
```

Sem Mac: todo push roda build + testes no GitHub Actions (`.github/workflows/ios.yml`).

Versão web (PWA, dados locais, backup compatível com o iPhone): [web/README.md](web/README.md).

TestFlight: [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md). Servidor do assistente: [backend/README.md](backend/README.md).

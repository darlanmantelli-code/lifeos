# livo

*sua vida mais inteligente*

App iOS pessoal (SwiftUI, iOS 17+). Arquitetura e plano: [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## Build

Precisa de macOS com Xcode 16+.

```
brew install xcodegen
xcodegen generate
open Livo.xcodeproj
```

Sem Mac: todo push roda build + testes no GitHub Actions (`.github/workflows/ios.yml`).

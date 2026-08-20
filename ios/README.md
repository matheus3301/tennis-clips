# Tennis Clips para iPhone

Aplicativo nativo SwiftUI que executa todo o pipeline no próprio iPhone. Não há
backend, upload nem dependência do projeto Python em runtime.

## Pipeline on-device

```mermaid
flowchart LR
    A[PhotosPicker] --> B[AVAssetReader]
    B --> C[PCM mono 16 kHz]
    C --> D[Accelerate FFT]
    D --> E[Regras espectrais]
    E --> F[ClipPlanner]
    A --> G[AVMutableComposition]
    F --> G
    G --> H[AVAssetExportSession]
    H --> I[MP4 local]
    I --> J[Revisar e compartilhar]
```

O detector nativo replica o princípio da versão Python validada: procura
transientes fortes e filtra pela distribuição de energia em bandas. Os eventos
viram janelas de rally de 1,2 s antes e 2,6 s depois, unidas quando se sobrepõem.

## Abrir

O projeto é gerado por XcodeGen:

```bash
cd ios
xcodegen generate
open tennis-clips.xcodeproj
```

Requisitos:

- Xcode completo com um runtime de iOS Simulator;
- iOS 17 ou mais recente;
- assinatura Apple configurada apenas para instalar em um iPhone físico.

Se as ferramentas de linha de comando ainda apontarem para o pacote isolado,
ative o Xcode completo e conclua sua preparação inicial:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

O app foi validado no Xcode 26.6 com um iPhone 17 Pro no iOS Simulator 26.5.

O pacote `core/` contém modelos e a lógica pura de montagem dos rallies. Ele pode
ser testado sem Xcode:

```bash
swift test --package-path ios/core
```

## Estado da implementação

- importação de vídeo com PhotosPicker;
- leitura e análise espectral do áudio no aparelho;
- criação e união das janelas de rally;
- montagem e exportação local com AVFoundation;
- reprodução, resumo e compartilhamento do resultado;
- sem rede e sem backend.

A validação visual por movimento ainda é o próximo estágio do port para Swift.
Até ela entrar, os filtros espectrais são a única evidência de impacto no app.

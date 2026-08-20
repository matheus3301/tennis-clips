# Auditoria completa do aplicativo iOS — Tennis Clips

Data da auditoria: 20 de agosto de 2026

Escopo: produto, funcionalidades, design visual, copy, acessibilidade, Swift/SwiftUI, Liquid Glass, concorrência, persistência, processamento, performance, testes e prontidão de distribuição.

Código auditado: `ios/` na versão `0.2.0 (1)`.

## Estado atual após a implementação

Esta seção é a fonte de verdade do documento. Os achados detalhados mais abaixo preservam o baseline anterior à intervenção para manter contexto e rastreabilidade; números de linha e frases no presente daquele baseline podem ter mudado.

### Veredito atualizado

Os blockers P0 identificados na auditoria foram corrigidos na base de código. O app agora compila em Swift 6 com concorrência estrita, respeita light/dark, usa Liquid Glass seletivamente, tem tipografia adaptativa, persistência versionada, fluxo multi-vídeo resiliente, gestão de armazenamento, App Icon, pt-BR, App Intents e um fluxo central sem os dead-ends encontrados no baseline.

Classificação atual: **release candidate de engenharia para iPhone, ainda dependente de validação assinada, aparelho físico e calibração do detector antes de distribuição ampla**.

### Respostas diretas atualizadas

#### Já existe modo light e dark?

**Sim.** O app respeita o tema do sistema por padrão e oferece “Sistema / Claro / Escuro” em Ajustes. A paleta inteira usa assets semânticos com variantes light/dark. Os dois modos foram executados e inspecionados no Simulator.

#### Já usa Liquid Glass?

**Sim, com escopo deliberado.** Toolbars e sheets usam o comportamento nativo do iOS 26; CTAs customizados e toast aplicam `glassEffect` explicitamente no iOS 26, com fallback de material no iOS 17–25. Cards de conteúdo permanecem opacos para preservar legibilidade e identidade visual.

#### Já usa Swift e SwiftUI modernos?

**Sim nos fundamentos relevantes ao produto.** A base usa Swift 6, strict concurrency, MainActor no target de UI, Observation, SwiftData com schema/migration plan, navegação tipada, `AppIntent`/`AppEntity`, `PhotosPicker`, `ShareLink`, `sensoryFeedback`, `ContentUnavailableView`, APIs assíncronas do AVFoundation e APIs condicionais do iOS 26.

### Entregas implementadas

| Área | Estado atual |
| --- | --- |
| Swift 6 | `SWIFT_VERSION: 6.0`, `SWIFT_STRICT_CONCURRENCY: complete`; build estrito passa |
| Concorrência | UI isolada no MainActor; tipos de processamento explicitamente não isolados/actors; progresso coalescido |
| Dark/light | tokens adaptativos e preferência Sistema/Claro/Escuro; validação visual nos dois temas |
| Liquid Glass | adoção explícita e seletiva no chrome/ações; fallbacks para iOS anterior ao 26 |
| Dynamic Type | tipografia semântica, CTA compacto em AX, revisão adaptada e telas críticas roláveis |
| Acessibilidade | Reduce Motion, feedback sensorial moderno, rail distinguível sem depender apenas de cor, labels e alvos nativos |
| Multi-vídeo | falha de uma gravação não invalida as demais; erro parcial identifica o arquivo |
| Gestão de gravações | adicionar/remover após criação, limite de oito, validação e reanálise informada |
| Edição de sessão | nome, data, tipo e adversário editáveis |
| Revisão | pause/play, incluir/descartar, desfazer, ajuste de início/fim, dividir/unir e compartilhar clip |
| Compilação | zero incluídas bloqueia CTA com explicação; recompile e revisão continuam disponíveis após conclusão |
| Retry | distingue falha de análise de falha de exportação e repete a operação correta |
| Processamento | interface focada em progresso, sem ação destrutiva permanente; cancelamento técnico permanece interno |
| Armazenamento | preflight de espaço, reserva de 500 MB, limite de 30 min por vídeo, uso em Ajustes → Informações e exclusão de backup |
| Exclusão | sessão e gravação removidas com staging/rollback para manter banco e arquivos consistentes |
| SwiftData | schema V1 e migration plan; fallback temporário se o store persistente não abrir |
| Navegação | `AppRoute` tipada, deep link `tennisclips://session/<UUID>` e Live Activity direcionada à sessão |
| Biblioteca | busca, filtros, continuação direta, adversário, status e rail agregado para sessões longas |
| Sistema | App Intents “Abrir nova sessão”, “Continuar revisão” e “Abrir sessão” com `AppEntity` |
| Exportação | alta qualidade ou compacta; salvar nas Fotos separado de incluir na compilação |
| Diagnóstico | relatório local compartilhável sem nomes nem mídia, com versão, SO e contagens agregadas |
| Localização | idioma-fonte pt-BR, String Catalog e datas em português brasileiro |
| Release hygiene | Asset Catalog adaptativo, App Icon 1024 sem alpha, metadata de App Intents e Live Activity no archive |
| Dependências | Lottie 4.6.1 mantido por decisão de produto para a animação de processamento, com asset local e suporte a Reduce Motion |

### Evidências finais

| Validação | Resultado |
| --- | --- |
| Build & Run Debug, iPhone 17 Pro / iOS 26.5 | Passou via XcodeBuildMCP |
| Build Release no Simulator | Passou |
| Archive genérico Release para iPhone, sem assinatura | Passou |
| Testes do target iOS | 11/11 passaram |
| Testes do pacote core | 3/3 passaram |
| Extração de metadata App Intents | Passou |
| Treino de frases App Shortcuts em pt-BR | Passou |
| Bundle do archive | contém `Assets.car`, App Icon, `Metadata.appintents` e Live Activity `.appex` |
| Store existente no Simulator | abriu preservando as duas sessões anteriores |
| Inspeção visual light/dark | passou |
| Dynamic Type AX máximo | fluxo crítico permanece rolável e acionável; revisão usa layout compacto dedicado |
| Deep link para sessão inexistente | abre o app e mostra recuperação “Sessão não encontrada” |

Archive técnico gerado em `/tmp/TennisClipsAuditFinal-20260820.xcarchive`. Ele prova a integridade do produto para `iphoneos`, mas não substitui um archive assinado nem a validação do App Store Connect.

### Pendências que permanecem reais

1. **Detector em streaming:** o limite de 30 minutos torna o pico de memória finito, mas o áudio ainda é materializado em memória. Reescrever o filtro zero-phase e o percentil em chunks exige uma fixture de paridade e profiling em aparelho; não deve ser feito sem validar a precisão.
2. **Calibração visual:** aspect ratio foi corrigido, mas hue/ROI/thresholds ainda precisam de dataset com roupas, quadras, iluminação, distâncias e orientações variadas.
3. **Aparelho físico:** medir memória residente, CPU, energia, thermal state, duração de processamento e interrupções com vídeos reais de 10/30 minutos.
4. **Validação assistiva completa:** executar Accessibility Inspector e uma passagem manual com VoiceOver, Increase Contrast, Differentiate Without Color e Reduce Motion em hardware.
5. **Distribuição:** configurar Team/certificados, gerar archive assinado e validar/upload no App Store Connect.
6. **Background no iOS 17–25:** o produto agora informa que deve permanecer aberto; execução continuada garantida permanece exclusiva do caminho iOS 26. Decidir entre manter esse contrato ou elevar o deployment target.
7. **Automação de UI:** criar UI tests/snapshots permanentes para light, dark, AX, importação, revisão, falha e conclusão. A inspeção atual foi manual/semântica no Simulator.
8. **Evoluções opcionais:** indexação Spotlight explícita, cache de thumbnails persistente e iPad/landscape continuam fora do escopo atual de iPhone.

## Baseline original antes da implementação

> As seções abaixo registram o estado encontrado no início da auditoria. Consulte “Estado atual após a implementação” para saber o que já foi corrigido.

### Veredito executivo original

O Tennis Clips já é um MVP funcional e visualmente autoral. O fluxo central — importar gravações, detectar rallies no aparelho, revisar, compilar, salvar e compartilhar — existe, compila e roda no iOS 26.5. A linguagem visual também está bem ancorada no tênis: quadra, linha, bola, placar e trilho de rallies formam uma identidade mais específica do que a média dos apps SwiftUI iniciais.

Ele ainda não está pronto para ser tratado como produto iOS tecnicamente completo ou pronto para distribuição ampla. Os principais bloqueios são:

1. o modo escuro está explicitamente desativado;
2. não há adoção explícita das APIs de Liquid Glass — apenas o vidro automático dos controles do sistema no iOS 26;
3. o projeto usa modo de linguagem Swift 5.0 e não compila com concorrência estrita do Swift 6;
4. um único vídeo sem impactos encerra toda uma sessão com vários vídeos;
5. não há exclusão/gestão de armazenamento na interface, embora duas sessões já ocupem 1,3 GB no Simulator;
6. Dynamic Type em tamanho de acessibilidade degrada fortemente a hierarquia e o layout;
7. faltam localização, App Icon e outros itens básicos de prontidão de distribuição;
8. várias ações e dados existem no modelo, mas não chegam ao produto.

Classificação atual: **MVP validado, com boa direção visual, mas com dívida P0 de acessibilidade, resiliência, armazenamento e modernização Swift.**

### Respostas diretas originais

### Já existe modo light e dark?

**Light: sim. Dark: não.**

`TennisClipsApp.swift:25` força o app inteiro para light:

```swift
RootView()
    .environment(model)
    .preferredColorScheme(.light)
```

O teste no Simulator, após mudar o sistema para dark, confirmou que o app permanece claro. Além disso, `AppPalette.swift` usa RGBs fixos, sem variantes adaptativas em Asset Catalog.

### Já usa Liquid Glass?

**Parcialmente e apenas de forma automática.**

No iOS 26, botões de toolbar, back button e a apresentação nativa da sheet recebem a aparência Liquid Glass do sistema porque o app é compilado com o SDK 26.5. Isso ficou visível no Simulator.

Por outro lado, não há nenhuma ocorrência de:

- `glassEffect()`;
- `GlassEffectContainer`;
- `.buttonStyle(.glass)`;
- `.buttonStyle(.glassProminent)`;
- `glassEffectID`.

As superfícies customizadas ainda usam cores opacas ou `.ultraThinMaterial`. Portanto, a resposta correta é: **o chrome do sistema adota Liquid Glass automaticamente, mas o design system do app ainda não o adotou.**

### Já usa as APIs mais novas do SwiftUI?

**Em parte.** O app usa `NavigationStack`, Observation (`@Observable`), SwiftData, `#Preview`, `.task`, `PhotosPicker`, `ShareLink`, `ContentUnavailableView`, `foregroundStyle`, `contentTransition` e APIs assíncronas modernas do AVFoundation.

Mas ainda há legado ou lacunas relevantes:

- linguagem configurada como Swift 5.0;
- concorrência estrita desativada;
- haptics via UIKit em vez de `sensoryFeedback`;
- `GeometryReader` onde o layout pode ser modernizado;
- navegação tipada misturada com `NavigationLink(destination:)`;
- `String(format:)` em UI e persistência;
- `Binding(get:set:)` construído dentro da View;
- UIKit importado em Views para haptics;
- materiais antigos onde Liquid Glass seria apropriado;
- fontes fixas que não escalam com Dynamic Type.

### Evidências executáveis originais

| Validação | Resultado |
| --- | --- |
| Xcode | 26.6 (build 17F113) |
| Compilador instalado | Swift 6.3.3 |
| Build Debug + launch, iPhone 17 Pro / iOS 26.5 | Passou |
| Build Release genérico para iPhone | Passou |
| Testes do target do app | 3 passaram |
| Testes do pacote core | 3 passaram |
| Build com `SWIFT_VERSION=6` e concorrência estrita | Falhou com 3 erros em `ProcessingActivityController.swift` |
| Build com isolamento MainActor aplicado ao grafo inteiro | Falhou também em `MotionValidator.swift:265` |
| Sistema em dark mode | App continuou em light |
| Dynamic Type máximo de acessibilidade | Layout funcionalmente degradado, com CTA inferior dominando a tela e títulos fixos fora de escala |
| Dados locais de duas sessões | 1,3 GB |
| Maior vídeo copiado para o app | 1,19 GB para ~9m56s |
| App Icon/`Assets.car` no bundle Release | Ausente |

Não foram executados nesta rodada: upload/validação no App Store Connect, profiling em aparelho físico, teste térmico de vídeos longos, VoiceOver manual completo, captura de energia ou teste de interrupção real pelo sistema. Os riscos de performance abaixo são, portanto, **code-backed**, não trace-backed.

### Mapa de prioridade original

### P0 — corrigir antes de chamar o app de pronto

1. **Resiliência do processamento multi-vídeo:** não abortar a sessão inteira por causa de um vídeo vazio ou inválido.
2. **Swift 6:** migrar o app para modo de linguagem Swift 6 e corrigir concorrência estrita.
3. **Acessibilidade:** remover tamanhos tipográficos rígidos e validar layouts nos tamanhos AX.
4. **Dark mode:** remover o bloqueio light-only e criar tokens adaptativos.
5. **Armazenamento:** adicionar exclusão, preflight de espaço, política de retenção e exclusão de backup para mídia recriável.
6. **Prontidão de distribuição:** App Icon, localização pt-BR, String Catalog e validação de archive.
7. **Persistência:** não encerrar o app com `fatalError` quando o store falhar e preparar migrações versionadas.

### P1 — fechar o produto central

1. expor excluir, editar sessão e cancelar processamento;
2. permitir corrigir cortes, não apenas aceitar/rejeitar;
3. separar “salvar nas Fotos” de “incluir na compilação”;
4. resolver o dead-end de zero jogadas incluídas;
5. tornar falhas acionáveis e identificar qual gravação falhou;
6. tornar o processamento em background honesto no iOS 17–25;
7. melhorar a Live Activity com deep link e progresso “vídeo X de Y”.

### P2 — evolução e diferenciação

1. busca/filtros no histórico;
2. App Intents para “Continuar revisão” e “Abrir nova sessão”;
3. Spotlight para sessões concluídas e pendentes;
4. cache de thumbnails e métricas de performance;
5. exportação configurável e compartilhamento de clip individual;
6. suporte opcional a iPad/landscape, se fizer sentido para o público.

## Achados originais por arquivo

### `project.yml`

#### P0 — o compilador é novo, mas o projeto está em modo Swift 5.0

Linhas 5–9:

```yaml
deploymentTarget:
  iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: 5.0
```

O target iOS 17 não é um erro por si só; é uma decisão de alcance. Já `SWIFT_VERSION: 5.0` impede que a base receba a validação do Swift 6. O build diagnóstico em Swift 6 estrito falhou em `ProcessingActivityController.swift:20,61,73` por risco de data race com `Activity`.

Direção recomendada:

```yaml
settings:
  base:
    SWIFT_VERSION: 6.0
    SWIFT_STRICT_CONCURRENCY: complete

targets:
  TennisClips:
    settings:
      base:
        SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
```

O isolamento MainActor deve ser aplicado ao target de UI, não indiscriminadamente ao pacote de processamento. O core deve continuar explicitamente não isolado ou actor-isolated onde necessário.

Decisão de produto pendente:

- manter iOS 17 e adicionar fallbacks para iOS 26; ou
- subir o deployment para iOS 26 e simplificar a base.

Se alcance não for requisito, o baseline moderno é iOS 26. Se alcance importar, Swift 6 ainda deve ser adotado independentemente do deployment target.

#### P0 — não existe App Icon nem Asset Catalog

O projeto configura `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, mas não existe `.xcassets`, e o bundle Release não contém `Assets.car`. O build local passa, porém a distribuição fica incompleta e a instalação usa ícone genérico.

#### P1 — dependência de Lottie para uma única animação

Lottie 4.6.1 é a única dependência externa. Ela está corretamente pinada e contém privacy manifest, mas aumenta superfície de atualização e tamanho por uma única animação. Não é necessário removê-la agora; vale comparar com uma animação SwiftUI/Core Animation nativa quando a modernização visual for feita.

### `TennisClipsApp.swift`

#### P0 — dark mode explicitamente desativado

Antes:

```swift
.preferredColorScheme(.light)
```

Depois:

```swift
// Sem override: respeita a preferência do sistema.
```

Se houver necessidade de escolha manual, oferecer “Sistema / Claro / Escuro” e persistir apenas essa preferência.

#### P0 — corrupção ou migração de store causa crash deliberado

Linhas 9–18 usam `fatalError` se o `ModelContainer` não abrir. Em produção, uma migração incompatível ou store corrompido encerra o app sem recuperação.

Antes:

```swift
} catch {
    fatalError("Não foi possível abrir o histórico: \(error.localizedDescription)")
}
```

Direção:

- schema versionado e `MigrationPlan`;
- estado de recuperação com retry;
- opção segura de exportar diagnóstico/recriar banco preservando os vídeos;
- logging estruturado do erro.

### `design/AppPalette.swift` e `design/AppStyles.swift`

#### P0 — tokens não são adaptativos

Todos os RGBs são fixos. O app precisa de cores semânticas com variantes Any/Dark e, quando aplicável, contraste elevado.

Direção:

```swift
static let background = Color(.appBackground)
static let surface = Color(.appSurface)
static let primaryText = Color(.appPrimaryText)
```

Os colorsets devem definir light/dark e ser testados com Increase Contrast.

#### P0 — `displayType(size:)` quebra Dynamic Type

Linhas 33–37:

```swift
func displayType(size: CGFloat, weight: Font.Weight = .black) -> some View {
    font(.system(size: size, weight: weight, design: .default))
        .fontWidth(.condensed)
}
```

No tamanho AX máximo, os corpos escalam e os títulos permanecem praticamente fixos, invertendo a hierarquia visual.

Direção para iOS 26:

```swift
func displayType(_ style: Font.TextStyle = .title, scale: Double = 1.1) -> some View {
    font(Font.system(style, design: .default).scaled(by: scale).width(.condensed).bold())
}
```

Validar cada tela em `accessibilityExtraExtraExtraLarge`; não limitar Dynamic Type globalmente para esconder problemas.

#### P1 — custom button styles ignoram o vocabulário de interação do iOS 26

Os estilos opacos têm boa identidade e não precisam virar vidro em todos os lugares. Ainda assim, floating actions e barras devem usar Liquid Glass nativo no iOS 26, com fallback para iOS 17–25.

Uso recomendado:

- CTA primário persistente: avaliar `.glassProminent` com tint da marca;
- CTA secundário/floating: `.glass`;
- cards de conteúdo e thumbnails: manter opacos;
- não aplicar vidro em cada card.

### `models/ProductModels.swift`

#### P1 — dados coletados ou calculados não chegam à experiência

`opponent`, `impactCount` e `confidence` são persistidos, mas nunca exibidos. Isso aumenta modelo e complexidade sem valor visível.

Opções:

- exibir adversário nos cards/detalhes;
- usar confiança para sinalizar “revise este corte” ou ordenar os casos duvidosos;
- exibir impactos apenas se ajudarem a explicar o corte;
- remover campos que não tiverem função de produto.

#### P1 — schema sem versionamento explícito

Para uma versão 0.2 pode funcionar por migração automática, mas o próximo ciclo deve introduzir `VersionedSchema` e testes de migração antes de evoluir entidades e relacionamentos.

#### P2 — múltiplos tipos no mesmo arquivo

O arquivo contém `SessionKind`, `SessionStatus`, `RallyDecision`, `TennisSession`, `SessionVideo` e `RallyClip`. Separar por tipo/feature reduz conflitos e deixa a evolução do schema mais segura.

### `models/AppModel.swift`

#### P0 — um vídeo sem impactos aborta toda a sessão

`OnDeviceTennisProcessor.analyze` lança `.noImpacts` por vídeo. Em `AppModel.swift:245–283`, o primeiro throw sai do loop e marca toda a sessão como failed, mesmo que vídeos anteriores ou posteriores tenham rallies válidos.

Direção:

```swift
for video in session.sortedVideos {
    do {
        let analysis = try await analyzer.analyze(videoAt: url, progress: progress)
        append(analysis)
    } catch ProcessingError.noImpacts {
        markVideoAsSkipped(video, reason: .noRallies)
        continue
    }
}

guard !session.clips.isEmpty else {
    throw ProcessingError.noImpactsInSession
}
```

A UI deve informar “2 de 3 gravações tinham jogadas”, em vez de falhar silenciosamente ou genericamente.

#### P0 — erros de persistência são engolidos

Linhas 121, 131, 182, 204, 306 e 381 usam `try? context.save()`. Uma ação pode parecer concluída mesmo quando não foi persistida.

Antes:

```swift
try? context.save()
```

Depois:

```swift
do {
    try context.save()
} catch {
    present(.persistenceFailed(error))
}
```

O modelo precisa de um estado de feedback tipado, não apenas `String?`.

#### P1 — “salvar nas Fotos” também inclui o clip no vídeo

Linhas 178–183 alteram `.pending` para `.kept` após salvar. A pessoa vê três ações distintas — descartar, salvar, incluir — mas salvar executa duas delas e avança a revisão.

Isso viola a consistência da linguagem de interface. Salvar deve salvar; incluir deve incluir. Se a combinação for intencional, o label deve dizer “Salvar e incluir”.

#### P1 — exclusão existe no modelo, mas não no produto

`delete(_:context:)` existe nas linhas 200–205 e não possui nenhum call site na UI. Resultado: mídia duplicada cresce sem mecanismo de limpeza.

#### P1 — não existe cancelamento exposto

O modelo sabe cancelar internamente, mas não oferece ação pública para interromper análise/exportação. Em processamento longo, a pessoa fica sem controle.

#### P1 — feedback de erro e sucesso usa o mesmo canal

`toastMessage: String?` não carrega severidade, título ou ação de recuperação. Isso faz erros aparecerem com o check de sucesso de `ToastView`.

Direção:

```swift
enum AppNotice: Identifiable {
    case success(String)
    case error(message: String, recovery: RecoveryAction?)
}
```

#### P2 — copy de contagem não usa inflection

Exemplo em `AppModel.swift:287`: `"1 jogadas prontas"` é possível. Usar String Catalog/inflection ou uma função localizada única para todas as contagens.

### `views/RootView.swift`

#### P1 — toast sempre mostra ícone de sucesso

`ToastView` usa `checkmark.circle.fill` mesmo quando a mensagem veio de um erro de exportação ou permissão. O componente deve variar semanticamente e permitir uma ação como “Abrir Ajustes”.

#### P1 — Reduce Motion não cobre as transições globais

O toast usa move + spring sem consultar `accessibilityReduceMotion`. Com Reduce Motion, usar apenas opacity.

#### P1 — material antigo em uma superfície perfeita para Liquid Glass

O toast usa `.ultraThinMaterial`. No iOS 26, é um candidato direto a `glassEffect`, agrupado em `GlassEffectContainer` apenas se coexistir com outras superfícies de vidro.

### `views/LibraryView.swift`

#### P1 — título de navegação duplicado

No estado com histórico, “Histórico” aparece no navigation bar e novamente como display title no conteúdo. O resultado visual parece duas hierarquias concorrentes.

Escolher uma estratégia:

- large navigation title que colapsa; ou
- título editorial no conteúdo e navigation bar sem título no topo.

#### P1 — histórico sem gestão

Faltam:

- excluir com confirmação;
- editar nome, data, tipo e adversário;
- busca/filtro quando a biblioteca crescer;
- indicador de espaço ocupado;
- ação de continuar revisão diretamente no card.

#### P1 — datas seguem o locale do aparelho, enquanto a copy é fixa em português

O teste no Simulator exibiu “20 August 2026” dentro de uma interface em português. Isso é um bug de localização/copy, não apenas preferência estética.

#### P1 — rail deixa de comunicar em sessões grandes

Com 46 rallies, os marcadores viram uma sequência de pontos quase indistinguíveis. Acima de um limiar, substituir por progresso agregado (`30 incluídas · 16 descartadas`) ou agrupar em páginas/blocos.

#### P2 — `caption2` e opacidades baixas

O badge do tipo usa `caption2`, e vários textos pequenos usam `ink.opacity(0.5–0.58)`. Devem ser medidos com Accessibility Inspector; visualmente, há risco de contraste insuficiente para texto pequeno.

### `views/NewSessionView.swift`

#### P0 — Dynamic Type máximo degrada a tela

No tamanho AX máximo, o texto introdutório ocupa quase toda a viewport e o CTA fixo inferior cresce para uma área dominante. O título display continua menor porque usa tamanho fixo. A tela ainda pode rolar, mas a ordem e a proporção deixam de ser utilizáveis com conforto.

Correções:

- tipografia escalável;
- `ViewThatFits`/layout vertical alternativo para o CTA;
- reduzir copy introdutória nos tamanhos AX;
- testar formulário, teclado e CTA em todos os tamanhos de acessibilidade.

#### P0 — vídeos que falham na importação são ignorados silenciosamente

Linhas 193–198 usam `continue` quando `loadTransferable` retorna nil. Se 1 de 8 falhar, a sessão pode ser criada com 7 sem qualquer aviso.

Direção:

```swift
guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
    throw ImportError.failedItem(index: index)
}
```

Ou apresentar um resumo explícito: “7 importados, 1 não pôde ser lido”, com escolha entre continuar ou corrigir.

#### P1 — “Tentar novamente” não tenta novamente

O botão do alert possui closure vazia. Renomear para “OK” ou executar de fato a importação novamente.

#### P1 — falta preflight de armazenamento e duração

Antes de copiar até oito vídeos, verificar espaço disponível, duração e formato. O erro atual só chega depois de trabalho e cópia parcial.

#### P2 — binding manual dentro da View

`errorBinding` usa `Binding(get:set:)`. Preferir um estado de apresentação tipado (`ImportError?`) com `.alert(item:)` ou equivalente.

### `views/SessionDetailView.swift`

#### P1 — mistura dois modelos de navegação na mesma hierarquia

`RootView` registra `navigationDestination(for: UUID.self)`, mas `SessionDetailView.swift:123` e `:168` usam `NavigationLink(destination:)`. Centralizar em um enum `Route: Hashable` e usar apenas `NavigationLink(value:)` + um único `navigationDestination(for:)`.

#### P1 — zero clips incluídos termina em CTA inválido

Após descartar tudo, a sessão vira `.ready`, mostra “0 jogadas vão para o vídeo” e mantém “Montar meu vídeo”. O botão só produz um toast de erro.

Melhor experiência:

- CTA “Rever escolhas” como primário;
- “Montar vídeo” desabilitado com explicação;
- ou permitir concluir a sessão sem compilação.

#### P1 — tela concluída não permite voltar e remontar

Depois da compilação, a pessoa só pode salvar ou compartilhar. Não há acesso às escolhas, edição dos cortes ou recompilação.

#### P1 — layout concluído é frágil com Dynamic Type

`GeometryReader` calcula altura do player com `availableHeight - 250`, assumindo uma altura quase fixa para todo o resto. Textos maiores quebram essa premissa. Usar layout fluido em `ScrollView`, `containerRelativeFrame` ou `ViewThatFits`.

#### P2 — `String(format:)` para duração

`TimeInterval.shortDuration` usa C formatting. Preferir `Duration.TimeFormatStyle`/`FormatStyle` localizado.

#### P2 — arquivo grande com muitos tipos

O arquivo possui 353 linhas e sete Views/estruturas. Separar por estado da feature: processing, review ready, summary, completed e failure.

### `views/RallyReviewView.swift`

#### P1 — haptics via UIKit

Linhas 199–200 e 227 usam `UINotificationFeedbackGenerator`/`UISelectionFeedbackGenerator`.

Antes:

```swift
UINotificationFeedbackGenerator().notificationOccurred(.success)
```

Depois, no nível da View:

```swift
.sensoryFeedback(.success, trigger: lastDecision)
```

Isso elimina o import UIKit da View e respeita melhor o sistema.

#### P1 — vídeo reproduz automaticamente e não oferece pause durante a revisão

O clip reinicia em loop e a tela não possui controle de play/pause. Isso é uma lacuna de acessibilidade, controle e análise precisa do corte.

#### P1 — Reduce Motion é parcial

O card rotaciona, se desloca e anima com spring sem consultar Reduce Motion. Para esse modo, manter feedback por opacity/estado e reduzir o deslocamento.

#### P1 — “Concluir” não conclui necessariamente

O botão apenas fecha a revisão mesmo com itens pendentes. “Pausar revisão” ou “Sair” descreve melhor a ação; “Concluir” deve ficar reservado para o final real.

#### P1 — revisão não corrige o detector

O produto só permite incluir/descartar. Para o fluxo ser confiável, faltam pelo menos:

- ajustar início/fim;
- dividir ou unir rallies;
- reportar “não é uma jogada”/“corte incompleto” para calibração local;
- visualizar confiança quando baixa.

### `components/RallyRail.swift`

#### P1 — decisão depende principalmente de cor

Kept/rejected/pending variam por cor e tamanho. Adicionar forma, traço ou símbolo e respeitar `accessibilityDifferentiateWithoutColor`.

#### P2 — API de enumeração desnecessariamente materializada

Antes:

```swift
ForEach(Array(decisions.enumerated()), id: \.offset)
```

Depois:

```swift
ForEach(decisions.enumerated(), id: \.offset)
```

#### P2 — `GeometryReader` pode virar `Layout` customizado

O uso atual é justificável para posicionamento, mas um `Layout` dedicado tornaria o componente mais moderno, testável e adaptável a dezenas de pontos.

### `components/VideoThumbnailView.swift`

#### P1 — todas as thumbnails são serializadas e não existe cache

Um actor singleton processa uma imagem por vez. Ao reabrir uma biblioteca grande, os mesmos frames são extraídos novamente e a lista pode aparecer gradualmente por muito tempo.

Adicionar:

- cache em memória com custo;
- thumbnail persistida por sessão;
- invalidação pelo path/modification date;
- prioridade/cancelamento para células fora da tela.

### `services/SessionStorage.swift`

#### P0 — duplicação de mídia sem política de armazenamento

Cada vídeo escolhido é movido/copiado integralmente para `Library/Application Support`. No Simulator auditado:

- duas sessões: 1,3 GB;
- um vídeo de 9m56s: 1,19 GB;
- compilação: ~94 MB.

Não há preflight, limite, compressão, limpeza nem UI de exclusão.

#### P0 — mídia recriável não está excluída de backup

Não foi encontrada marca de exclusão de backup. Conteúdo em Application Support é elegível a backup por padrão. Isso pode tornar a promessa “Seus vídeos não saem do iPhone” tecnicamente imprecisa quando iCloud Backup está ativo, além de enviar grandes arquivos recriáveis para backup.

Aplicar `URLResourceValues.isExcludedFromBackup = true` às fontes e clips recriáveis, e revisar a copy de privacidade com precisão.

#### P1 — risco de inconsistência na exclusão

`AppModel.delete` remove os arquivos antes de confirmar a exclusão no banco. Se `context.save()` falhar, o registro pode sobreviver apontando para arquivos já removidos. Persistir/tombstonar primeiro ou implementar rollback.

### `services/ImpactDetector.swift`

#### P0/P1 — memória cresce linearmente com a duração do vídeo

Todo o áudio mono 16 kHz é materializado em `[Float]`, e o detector cria buffers `[Double]` por banda. Para vídeos longos, o pico pode chegar a centenas de MB. Não houve memgraph nesta rodada, portanto a severidade de runtime é hipótese sustentada pelo código.

Direção:

- leitura e envelope em streaming/chunks com overlap;
- percentil aproximado ou primeira passagem compacta;
- evitar múltiplas conversões completas para Double;
- testes de 10, 30 e 60 minutos em aparelho físico;
- medir peak resident memory, CPU, energia e thermal state.

#### P1 — progresso gera fan-out excessivo

O callback pode atualizar estado de UI a cada sample buffer e criar Tasks de ActivityKit. Fazer throttle/coalescing antes de chegar ao MainActor.

### `core/MotionValidator.swift`

#### P1 — pressupostos visuais são rígidos e invisíveis para o usuário

O algoritmo:

- força frames para 270×480;
- procura roupa em uma faixa fixa de hue (`18...42`);
- usa ROI vertical e thresholds fixos;
- estica a imagem para o retângulo de análise sem preservar aspect ratio.

Isso favorece o cenário de teste e pode reduzir acurácia em landscape, outras cores de roupa, iluminação diferente ou câmera mais distante.

Recomendações:

- preservar aspect ratio e letterbox/crop conhecido;
- detectar orientação e geometria de quadra;
- validar dataset com roupas/quadras/iluminações variadas;
- informar boas práticas de gravação no onboarding;
- oferecer fallback/calibração de sensibilidade;
- criar testes específicos do motion gate, hoje ausentes.

### `services/ContinuedProcessingService.swift`

#### P1 — background confiável só existe no caminho iOS 26

Para iOS 17–25, o fallback apenas executa a operação dentro da Task normal. Live Activity não concede tempo de execução em background. Ao sair do app, processamentos longos podem ser suspensos enquanto a Live Activity permanece visível.

Opções:

- assumir iOS 26 como mínimo;
- implementar estratégia compatível para versões anteriores;
- ou comunicar claramente “mantenha o app aberto” nessas versões.

### `services/ProcessingActivityController.swift`

#### P0 — não passa em concorrência estrita Swift 6

O build diagnóstico falhou nas chamadas `end`, `update` e `end` porque valores `Activity` são enviados através de fronteiras que o compilador considera arriscadas.

Não resolver com `@unchecked Sendable` por conveniência. Isolar a integração ActivityKit em um domínio consistente e seguir a assinatura/conformidade disponível no SDK 26.

### `live-activity/TennisClipsActivityBundle.swift`

#### P1 — tocar na Live Activity não abre a sessão correspondente

Não há `widgetURL`/deep link nem roteamento em `RootView`. O toque abre o app genericamente, não o processamento específico.

#### P1 — estado contém vídeo atual/total, mas a UI não mostra

`currentVideo` e `totalVideos` são enviados e ignorados. Mostrar “Vídeo 2 de 8” aumenta confiança durante uma operação longa.

#### P2 — tipos e paleta duplicados

O target repete cores RGB e mantém várias Views no mesmo arquivo. Criar tokens compartilhados compatíveis com a extensão.

### `tests/` e `core/tests/`

#### P0/P1 — cobertura insuficiente para os riscos reais

Os seis testes passam, mas cobrem apenas defaults do modelo, transição simples de revisão, nome importado, ClipPlanner e uma fixture sintética do detector de áudio.

Faltam testes para:

- multi-vídeo com um vídeo sem impactos;
- falha parcial de importação;
- persistência e migração SwiftData;
- exclusão/rollback de arquivos;
- exportação com orientações e frame rates mistos;
- cancelamento e retomada;
- continued processing e Live Activity;
- motion validator;
- zero clips incluídos;
- deep links;
- UI tests do fluxo crítico;
- snapshots light/dark e Dynamic Type.

## Auditoria de design

### O que está funcionando

- **Identidade específica:** hard court teal, ball yellow-green e clay red pertencem ao universo do tênis.
- **Assinatura visual:** o RallyRail funciona como linha de quadra/placar e cria continuidade entre biblioteca, detalhe e revisão.
- **Hierarquia fotográfica:** os vídeos são o conteúdo principal, não decoração.
- **Tom:** a copy evita jargão na maior parte do fluxo e transmite controle humano sobre o detector.
- **Privacidade como valor:** processamento on-device é um diferencial real e está bem posicionado.
- **Revisão acessível por alternativa:** o swipe tem botões equivalentes, o que é correto.

### O que enfraquece a experiência

- light-only contradiz expectativa de app moderno;
- títulos fixos deixam de funcionar com acessibilidade;
- navigation title duplicado com título editorial;
- muitos marcadores deixam de informar em sessões longas;
- ações de salvar/incluir têm semântica sobreposta;
- estado de erro usa aparência de sucesso;
- telas concluídas viram becos sem saída;
- custom materiais não conversam plenamente com o iOS 26;
- falta uma experiência de “como gravar bem” alinhada às limitações reais do detector.

### Direção visual recomendada

Preservar a direção atual. Não transformar o app em um conjunto genérico de cards de vidro.

Sistema proposto:

- **Background:** Chalk adaptativo — claro quente no light, azul-preto de quadra no dark;
- **Surface:** Court Mist adaptativo para cards de conteúdo;
- **Primary:** Baseline para ações e texto de marca;
- **Signal:** Ball apenas para progresso, confirmação e foco;
- **Destructive:** Clay Mark para descarte/erro;
- **Glass:** somente chrome flutuante, toast, CTA persistente e ações compactas.

Assinatura a manter: **RallyRail como placar temporal da sessão**, mas com versão agregada para grandes volumes e estados distinguíveis sem cor.

## Auditoria de copy e localização

| Copy atual | Problema | Direção recomendada |
| --- | --- | --- |
| “Concluir” durante revisão incompleta | Apenas fecha a tela | “Pausar revisão” |
| “Tentar novamente” no alert de criação | Closure vazia | “OK” ou retry real |
| “Nenhuma batida passou pelos filtros deste treino.” | Jargão interno e incorreto para jogo | “Não encontramos jogadas nesta gravação. Tente um vídeo com som mais claro ou escolha outra gravação.” |
| “0 jogadas vão para o vídeo” + CTA montar | Dead-end | “Nenhuma jogada incluída” + CTA “Rever escolhas” |
| Ícone de check + mensagem de erro | Semântica contraditória | Toast/alert de erro com ação de recuperação |
| “Seus vídeos não saem do iPhone” | Pode ser impreciso com backup | Excluir mídia de backup ou revisar para “O processamento acontece no iPhone; o app não envia seus vídeos para nossos servidores.” |
| “20 August 2026” em UI portuguesa | Locale inconsistente | String Catalog pt-BR e configuração de desenvolvimento/localização coerente |
| “1 jogadas” | Flexão ausente | String Catalog com pluralização/inflection |

Não existe `Localizable.xcstrings`. Todas as strings estão hardcoded e `CFBundleDevelopmentRegion` termina como `en` no bundle. Criar String Catalog com chaves simbólicas geradas e pt-BR como idioma base.

## Gaps de produto e funcionalidades

### Fluxo central

- adicionar/retirar vídeos de uma sessão já criada;
- editar nome, data, tipo e adversário;
- excluir sessão;
- cancelar processamento/exportação;
- corrigir início/fim de um rally;
- dividir/unir rallies;
- remontar vídeo concluído;
- lidar com vídeos parcialmente inválidos;
- indicar gravação que falhou;
- preflight de armazenamento;
- confirmação de quantos vídeos foram importados.

### Biblioteca

- busca e filtros por tipo/status/data;
- continuar revisão no card;
- espaço usado e limpeza;
- estado de mídia ausente/corrompida;
- metadados hoje invisíveis, como adversário.

### Sistema iOS

Primeiro pacote de App Intents recomendado:

1. **Continuar revisão** — resolve uma sessão pendente e abre diretamente nela;
2. **Abrir nova sessão** — abre a sheet de importação;
3. **Abrir sessão** — `AppEntity` mínima para Spotlight/Siri.

Não vale expor o pipeline inteiro a Shortcuts agora. A importação via PhotosPicker ainda deve ocorrer no app.

### Feedback e confiança

- guidance de gravação antes da primeira importação;
- explicação do que o detector procura;
- baixa confiança visível apenas quando for acionável;
- diagnóstico local opcional;
- métricas opt-in e privacy-preserving para falhas, duração e taxa de aceitação.

O README declara analytics fora do escopo. Isso é válido para o MVP, mas sem métricas o time não consegue medir precisão, abandono e custo do processamento. Se analytics continuar proibido, criar ao menos diagnóstico local exportável e métricas agregadas opt-in.

## Plano recomendado de execução

### Marco 1 — fundação técnica e release hygiene

1. App Icon + Asset Catalog + tokens dark/light;
2. String Catalog pt-BR e correções de plural/data;
3. Swift 6 + concorrência estrita;
4. schema SwiftData versionado e recuperação de store;
5. testes dos blockers;
6. archive real e validação App Store.

Critério de saída: Debug/Release/Archive passam sem warnings acionáveis; Swift 6 estrito passa; app inicia com store antigo e corrompido de teste.

### Marco 2 — confiabilidade do fluxo

1. processamento multi-vídeo tolerante a falhas;
2. importação com resumo e preflight;
3. excluir/editar/cancelar;
4. zero-kept e retry corrigidos;
5. separar salvar de incluir;
6. background por versão documentado/implementado.

Critério de saída: nenhum vídeo individual invalida a sessão inteira sem explicação; toda operação longa pode ser cancelada ou retomada.

### Marco 3 — acessibilidade e design iOS 26

1. tipografia escalável;
2. layouts AX com `ViewThatFits`/scroll fluido;
3. Reduce Motion completo;
4. estados distinguíveis sem cor;
5. Liquid Glass restrito ao chrome;
6. previews light/dark/AX para todos os estados.

Critério de saída: Accessibility Inspector sem blockers e validação manual com VoiceOver, Reduce Motion, Increase Contrast e AX máximo.

### Marco 4 — qualidade do detector e performance

1. pipeline de áudio em streaming;
2. preservação de aspect ratio no motion gate;
3. dataset variado e testes de motion;
4. cache de thumbnails;
5. profiling em dispositivo real.

Métricas mínimas: peak memory, CPU, energia, thermal state, tempo por minuto de vídeo, frame hitches da biblioteca e taxa de clips aceitos/rejeitados.

### Marco 5 — diferenciação de produto

1. ajuste manual de cortes;
2. deep links/Live Activity;
3. App Intents/Spotlight;
4. busca e gestão de biblioteca;
5. opções de exportação orientadas por uso real.

## Ordem sugerida para começarmos

1. **Swift 6 + correções de concorrência**, porque isso muda a fundação e expõe erros escondidos.
2. **Dark mode + Dynamic Type**, porque atravessam todas as Views.
3. **Multi-vídeo + armazenamento/exclusão**, porque são os maiores riscos reais de perda de confiança.
4. **Copy/localização e estados de erro**, porque são relativamente baratos e removem inconsistências visíveis.
5. **Liquid Glass**, depois que os tokens e layouts estiverem corretos; vidro não deve mascarar uma base ainda frágil.

---

Esta auditoria não alterou o comportamento do aplicativo. O único artefato criado é este relatório.

# Research

Projeto Python usado para reproduzir o protótipo original e explorar novos
detectores antes de portar decisões maduras para o aplicativo iOS.

O código estável de cortes contextuais e a camada analítica `v0.3.0` vivem no
mesmo ambiente de pesquisa. Nenhum módulo Python é necessário no iPhone.

## Preparar

Na raiz do repositório:

```bash
uv sync --project research
```

## Pipeline validado

```bash
uv run --project research tennis-clips make ~/Downloads/IMG_2842.MOV \
  --mode rallies \
  --output output/jogadas.mp4 \
  --manifest output/jogadas.json
```

O comportamento validado antes dos analytics está preservado na tag `v0.2.0`.

## Analytics experimental

Depois de gerar os eventos e a compilação contextual:

```bash
uv run --project research tennis-clips analytics ~/Downloads/IMG_2842.MOV
```

Essa camada inclui MediaPipe Pose, classificação heurística de golpes e overlay.
As métricas não devem migrar para o app sem nova validação.

## Testes

```bash
uv run --project research python -m unittest discover -s research/tests
```

Vídeos, modelos, caches e outputs continuam ignorados pelo Git.

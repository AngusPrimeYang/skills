# Spec labels

| File | Use |
|------|-----|
| `labels.zh-TW.json` | Default Traditional Chinese framing |
| `labels.en.json` | English framing (guide body still from Chinese call guides) |

Load via `Convert-GuidesToApiSpec.ps1 -Locale <id>` or `-LabelsPath`.
Keep UTF-8 with BOM. Do not put CJK literals in `.ps1`.

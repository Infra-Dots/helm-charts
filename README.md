# InfraDots Helm charts

```bash
helm repo add infradots https://infra-dots.github.io/helm-charts
helm repo update
```

| Chart | |
|---|---|
| [`infradots-runner`](charts/infradots-runner) | Run InfraDots in your own cluster. The agent runner reviews and implements infrastructure changes with your own model account; the executor runs Terraform/OpenTofu/Terragrunt. |

Docs: [infradots.com/docs/self-hosted-runners](https://infradots.com/docs/self-hosted-runners)

## Contributing

Each chart lives in `charts/<name>`. Bump its `version` in `Chart.yaml` with every change. Pull requests are linted,
schema-checked and installed on a kind cluster (`.github/workflows/lint-test.yaml`). A merge to `main` releases every
new chart version to the repository above.

Locally:
```bash
ct lint --config ct.yaml --all
helm template t charts/infradots-runner -f charts/infradots-runner/examples/with-executor.yaml
```

## License

[Apache-2.0](LICENSE). The license covers the charts; the runner images are distributed separately.

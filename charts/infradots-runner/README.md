# infradots-runner

Run InfraDots runners in your own Kubernetes cluster:

- **Agent runner** (`agent`, on by default) reviews pull requests and implements infrastructure changes, using
  **your own model account**: the Anthropic API, AWS Bedrock, Google Vertex AI or Azure AI Foundry.
- **Executor** (`executor`, off by default) runs your workspaces' Terraform, OpenTofu and Terragrunt plans and applies.

Both connect **out** to InfraDots over HTTPS, so nothing needs to reach into your cluster. Your repositories are
cloned, and your model calls made, from inside your network.

## Install

1. In InfraDots, open **Organization settings → Worker Pools** and create a pool. Use kind **agent** for the agent
   runner and kind **executor** for the executor. Copy the registration token: it's shown once.
2. Store the token, and your model provider's credentials, as Secrets:
   ```bash
   kubectl create namespace infradots
   kubectl -n infradots create secret generic infradots-agent-pool --from-literal=REGISTRATION_TOKEN=<token>
   kubectl -n infradots create secret generic anthropic --from-literal=ANTHROPIC_API_KEY=<key>
   ```
3. Install the chart:
   ```bash
   helm repo add infradots https://infra-dots.github.io/helm-charts
   helm -n infradots install runners infradots/infradots-runner \
     --set agent.registration.existingSecret=infradots-agent-pool \
     --set agent.model.existingSecret=anthropic
   ```
4. Check the runner's setup. This tests the configuration, the work directory, git, the connection and token, and
   makes one tiny request per model:
   ```bash
   kubectl -n infradots exec deploy/runners-infradots-runner-agent -- idp-agent doctor
   ```
5. Route work to the pool: set it as the **agent pool** of your organization or of individual workspaces. Executor
   pools are set per workspace, as its **worker pool**.

More setups are in [`examples/`](examples):

| File | Setup |
|---|---|
| [`anthropic-key.yaml`](examples/anthropic-key.yaml) | Anthropic API key |
| [`bedrock-irsa.yaml`](examples/bedrock-irsa.yaml) | AWS Bedrock via IRSA, with no static keys |
| [`vertex-workload-identity.yaml`](examples/vertex-workload-identity.yaml) | Google Vertex AI via GKE Workload Identity |
| [`with-executor.yaml`](examples/with-executor.yaml) | Agent runner plus executor |
| [`locked-down.yaml`](examples/locked-down.yaml) | Corporate egress proxy, with a NetworkPolicy |

## Your model account

InfraDots chooses which Claude model each agent uses. The runner only changes **where** the call goes:

| `agent.model.provider` | Credentials | `agent.model.map` |
|---|---|---|
| `anthropic` (default) | `ANTHROPIC_API_KEY` in `agent.model.existingSecret` | not needed |
| `bedrock` | IRSA or EKS Pod Identity (`serviceAccount.annotations`), plus `AWS_REGION` | `claude-opus-5: eu.anthropic.claude-opus-5-v1:0`, `claude-sonnet-5: …` |
| `vertex` | GKE Workload Identity, plus `CLOUD_ML_REGION` and `ANTHROPIC_VERTEX_PROJECT_ID` | `claude-opus-5: claude-opus-5@<version>`, … |
| `foundry` | `ANTHROPIC_FOUNDRY_API_KEY` and `ANTHROPIC_FOUNDRY_RESOURCE` in `agent.model.existingSecret` | your deployment names |

For any provider other than `anthropic`, map **every** model InfraDots uses. `doctor` tests each mapped model. A run
that needs a model the map lacks stops before it clones, and its message names the model to add.

Runs on your own model account don't count against your InfraDots AI interactions.

## Security

**Hardened by default:**
- runs as non-root (uid 1001), with a read-only root filesystem and every Linux capability dropped
- `RuntimeDefault` seccomp, and no privilege escalation
- no Kubernetes API token mounted
- writable space is limited to size-capped `emptyDir`s

**Credentials are scoped to one run.** InfraDots issues each run its own task token and a short-lived git credential
for that run's repository. The runner never holds a long-lived VCS secret, and its registration token is good only
for its own pool. To revoke a leaked token, use **Rotate token** on the pool; runners still using the old token stop
at their next request.

## Network

The runners only make outbound connections:

| Destination | Used by | For |
|---|---|---|
| Your InfraDots URL (`idpUrl`, default `app.infradots.com`), port 443 | both | registration, claiming work, results |
| Your git host (github.com, gitlab.com or your own) | both | cloning, and pushing the agent's branches |
| Your model provider's API | agent | model calls |
| `releases.hashicorp.com`, `api.github.com` and GitHub release downloads | both | Terraform/OpenTofu binaries, which can be mirrored (`*ReleasesUrl` values) |
| Terraform provider and module registries | executor | `terraform init` |

`networkPolicy.enabled` blocks all ingress and limits egress to DNS plus `networkPolicy.egress` (CIDRs and ports).
NetworkPolicy can't filter by hostname. To allow only the hosts above, route through an egress proxy (`proxy.*`) or
use your CNI's FQDN policies.

## Values

| Value | Default | |
|---|---|---|
| `idpUrl` | `https://app.infradots.com` | Your InfraDots URL |
| `agent.enabled` / `executor.enabled` | `true` / `false` | Which runners to deploy |
| `*.replicaCount` | `1` | Each replica handles one run or job at a time |
| `*.registration.existingSecret` / `.existingSecretKey` | — / `REGISTRATION_TOKEN` | The pool token's Secret (recommended) |
| `*.registration.token` | — | Or the token itself (the chart creates the Secret) |
| `agent.model.provider` / `.map` / `.existingSecret` | `anthropic` / `{}` / — | See *Your model account* |
| `agent.workDir.sizeLimit` | `10Gi` | Space for clones |
| `executor.executableCache.enabled` / `.sizeLimit` | `true` / `2Gi` | Keep Terraform binaries between jobs |
| `executor.terminationGracePeriodSeconds` | `3600` | On shutdown the executor finishes its current job first. Set this longer than your longest apply |
| `*.resources`, `*.nodeSelector`, `*.tolerations`, `*.affinity`, `*.extraEnv`, `*.extraEnvFrom` | | Usual pod settings |
| `serviceAccount.annotations` | `{}` | Workload identity (IRSA, GKE, Azure) |
| `proxy.httpsProxy` / `.httpProxy` / `.noProxy` | — | Egress proxy for both runners |
| `podSecurityContext` / `securityContext` | hardened | Override for e.g. OpenShift's random UIDs |
| `networkPolicy.*` | off | See *Network* |

`values.schema.json` rejects unknown keys and bad values at install time.

## Upgrades

Runners and InfraDots are versioned separately. InfraDots keeps working with the previous runner version, and a
runner too old for what InfraDots sends is marked **needs upgrade** on its pool. Upgrade with
`helm repo update && helm upgrade`. The agent runner reports a run interrupted by a restart, and the executor
finishes its current job before exiting.

## Troubleshooting

- **`idp-agent doctor`** checks everything the agent runner needs and says what to fix.
- **A runner doesn't show in its pool:** read its log (`kubectl logs`). It retries registration while InfraDots is
  unreachable. Check `idpUrl`, egress to it, and that the token is the pool's current one.
- **Runs wait in the queue:** the pool has no runner online, or its runners need an upgrade. Both show on the pool.

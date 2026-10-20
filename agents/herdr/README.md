# agents/herdr — agent workspace

Agents are plain Kubernetes workloads in namespace `agents` (ADR-0028, ADR-0036). The scaffold (ServiceAccount, egress
policy) is `gitops/base/agents/agents.yaml`; quota and PSS `restricted` come from `gitops/base/namespaces`.

- `image/`: Dockerfile of the Herdr workspace (built by `.github/workflows/herdr-image.yml`, pinned by digest below)
- `profiles/herdr-workspace.yaml`: StatefulSet `herdr`, network policies for the AI gateway and the `agent-workspace` bucket
- `enable/agent-profiles-app.yaml`: Argo CD app that deploys `profiles/`; not active yet

## Enable (needs the agent node)
1. Create the node (billable, about 6.53 EUR/month for a cx23): add `"agent-01" = { role = "agent", server_type = "cx23" }`
   to `nodes` in `production.tfvars`, plan, review, apply the saved plan.
2. Join it to k3s as an agent with label `workload=agent` and taint `workload=agent:NoSchedule` (cluster/bootstrap/k3s).
3. `git mv agents/herdr/enable/agent-profiles-app.yaml gitops/apps/agent-profiles.yaml`, commit, push.
4. `kubectl -n agents exec -it herdr-0 -- herdr`; install an agent CLI into `/home/agent` (persistent).

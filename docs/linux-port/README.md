# Box Linux Port Docs

This folder splits Linux-port implementation details by component so each area can be developed independently.

All new Linux-native implementation code should live at repository root (`cmd/`, `lib/`, `systemd/`, `tests/`).

## Documents
- `00-overall-architecture.md`
- `01-component-config-runtime-model.md`
- `02-component-bootstrap-and-service-manager.md`
- `03-component-core-supervisor.md`
- `04-component-firewall-routing.md`
- `05-component-updater-and-assets.md`
- `06-component-network-policy-watchers.md`
- `07-component-installer-packaging.md`
- `08-delivery-plan-and-risk-register.md`

## Source Baseline
All analysis is based on:
- Repo scripts under `box-reference/box/box/scripts/*`
- Module glue scripts (`box-reference/box/customize.sh`, `box-reference/box/box_service.sh`, `box-reference/box/action.sh`, `box-reference/box/uninstall.sh`)
- `settings.ini` and default core configs under `box-reference/box/box/`

Release module contents are in `box-reference/box_1.2.6.47a5185.zip` and `box-reference/box_1.2.6.47a5185_zip/`.

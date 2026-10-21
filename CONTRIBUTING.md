# Contributing to MiniThermal

Issues and pull requests may be written in English or Chinese. The maintainer is [RTXDF](https://github.com/RTXDF).

## Useful contributions

The project currently targets the M4 Mac mini (`Mac16,10`). Documentation, English localization, reproducible bug reports, simulated regression checks and read-only hardware evidence are useful starting points. See the [README roadmap](README.md#contribute-and-next-steps) for current priorities.

For a new hardware model or a substantial change to fan-control behavior, open an issue describing the evidence and intended behavior before implementing the change. Support for another machine requires more than a renamed model check.

## Report a problem

Open an [issue](https://github.com/RTXDF/MiniThermal/issues/new) and include:

- App version or commit, macOS version, and hardware model identifier.
- Steps to reproduce, expected behavior, and what actually happened.
- Whether the app was only monitoring or was in an authorized control session.
- Relevant error text or a redacted screenshot or diagnostic excerpt.

The `--diagnose` command in the README reads temperatures and RPM without writing to the fan. Review output before sharing it; omit serial numbers, account details, private paths and unrelated logs. Do not post passwords or credentials. You do not need to attempt privileged writes to file an issue.

## Set up development

Use an Apple Silicon Mac with macOS 14 or later, Python 3, and full Xcode with the developer tools selected.

```sh
git clone https://github.com/RTXDF/MiniThermal.git
cd MiniThermal
zsh scripts/build.sh
zsh scripts/test.sh
```

The build creates `build/MiniThermal.app`. Tests use simulated hardware and do not modify a real fan. Keep generated apps, local reports and screenshots out of a pull request unless they are explicitly needed as documentation assets.

| Area | Files |
| --- | --- |
| Menu bar app and startup | `Sources/App.swift`, `Sources/InstanceLock.swift` |
| Monitoring and authorization | `Sources/Monitor.swift` |
| SwiftUI panel | `Sources/Panel.swift` |
| SMC protocol, control and recovery | `Sources/ThermalSMC.c`, `Sources/ThermalSMC.h`, `Sources/helper.c` |
| Simulated checks | `Tests/`, `scripts/test.sh`, `scripts/test-instance-lock.sh` |
| Icons and packaging | `Assets/`, `scripts/build.sh`, `scripts/build-icons.sh` |

## Prepare a pull request

Fork the repository and create a branch for one focused change. Keep the current style of the files you edit, and preserve third-party attribution. Include:

1. The concrete problem and resulting behavior.
2. Relevant validation commands and their results.
3. Whether observations came from simulated tests or real hardware, including any remaining gaps.
4. Screenshots for visible interface changes, without unrelated desktop content.

For documentation-only changes, check links, commands and factual claims. For runtime changes, run the build and relevant existing tests. Add a regression check when a bug or control-path change needs one; avoid tests that only repeat implementation details.

For changes to the privileged helper, IPC, thermal policy or recovery behavior, explain the affected trust boundary and failure cases. Preserve bounds checks, model restrictions, temperature checks, heartbeat handling and restoration attempts. Do not turn simulated success into a claim that a hardware write succeeded. Record deliberate on-device validation separately in `VALIDATION.md`; physical fan writes are never a prerequisite for running the automated suite.

AI-assisted contributions are welcome. Review and understand the generated changes, verify their behavior, and describe material limitations in the pull request. Please keep discussions respectful and technical.

## License

By submitting a contribution, you agree that your contribution may be distributed under the project's [MIT License](LICENSE). Keep third-party license notices with any reused material and identify its source.

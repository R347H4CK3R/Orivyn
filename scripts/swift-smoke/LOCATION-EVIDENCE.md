# One-shot location lifecycle host proof

Run `python3 scripts/run_location_smoke.py --swiftc <installed Swift 6 compiler> --output <new proof directory>`.
The runner copies and hashes actual `LocationSnapshot.swift`, extracts the unchanged `LocationDriver` protocol and entire `OneShotLocationService` body, and compiles with the official static Swift Observation runtime. It excludes the Apple `SystemLocationDriver` adapter and substitutes an explicitly synthetic boundary. The source hash, exact extraction hash/parity, command, compiler version, compile/runtime logs, checks and exit codes are saved.

Initial proof: `/workspace/shared/orivyn-swift-validation/location-smoke-1`.
Compilation and execution returned zero; all **21 checks passed**, including a second execution of the same binary. Checks cover no driver before a request; repeated taps while busy; synchronous completion; cancellation of its timeout; preserving/clearing displayed results; stale callbacks after cancellation and replacement; denied permission results; nine invalid synthetic data cases; legitimate boundary coordinates/reduced accuracy; and timeout with late success.

All coordinates are fabricated test values and are not logged in the result. Real Observation, task scheduling, ownership guards and data validation execute. The driver deliberately retains canceled callbacks to challenge stale-result handling. No production behavior was changed and no defect was found in this bounded exercise.

This does **not** verify CoreLocation authorization prompts, CLLocationManager delegate behavior, foreground scene wiring, real hardware accuracy, the full app, or an iPhone build/device. Native tests and device checks remain required. A service-level denial result is not proof of an actual OS permission interaction.

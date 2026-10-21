# Third-party notices / 参考资料与授权

MiniThermal's own code and documentation are distributed under the [MIT License](LICENSE), copyright 2026 RTXDF. Third-party rights and notices remain with their respective authors.

The SMC wire protocol and M4 temperature-key mappings were informed by [Stats](https://github.com/exelban/stats), copyright (c) 2019 Serhiy Mytrovtsiy, under the MIT License. The complete notice is preserved in [References/Stats-LICENSE](References/Stats-LICENSE) and packaged with the application. MiniThermal independently implements its C interface, thermal policy, session helper and menu bar interface.

[macos-smc-fan's hardware research notes](https://github.com/agoodkind/macos-smc-fan/blob/main/docs/research.md) were consulted for fan-mode compatibility. They are a protocol reference, not a bundled runtime dependency.

## 简体中文

SMC 通信协议、M4 温度传感器键名参考 [Stats](https://github.com/exelban/stats)。本项目独立实现 C 接口、温控保护、会话辅助进程与中文菜单栏界面。Stats 的 MIT 授权全文位于 References/Stats-LICENSE，并随应用一同分发。

Copyright (c) 2019 Serhiy Mytrovtsiy。

风扇模式兼容性参考 [macos-smc-fan 的硬件研究记录](https://github.com/agoodkind/macos-smc-fan/blob/main/docs/research.md)。该记录仅用于理解协议行为，并未作为运行依赖。

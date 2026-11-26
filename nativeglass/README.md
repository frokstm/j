# ControlCenter26 Liquid Glass for iOS 18

This rewrite styles the built-in iOS 18 Control Center module containers. It does not add a Connectivity page, page-break modules, or replacement Wi-Fi/Bluetooth/Airplane Mode controls. Apple's modules continue to own their layout, controls, state, and actions.

The tweak finds the stock material views inside each module and adds a small adaptive sheen and rim. It has no LiquidAss dependency. On iOS 18 this is a glass-inspired treatment built on the system material; it is not Apple's native iOS 26 Liquid Glass renderer.

## Target

- iOS 18.x, rootless Dopamine
- `arm64e` only
- Built-in Control Center module views

The appearance hook is limited to `CCUIContentModuleContainerView` layout. It does not hook Control Center paging, connectivity actions, or slider actions.


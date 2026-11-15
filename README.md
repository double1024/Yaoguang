# 瑶光（Yaoguang）

瑶光是一个本地 ADS-B 航班接收项目。它使用 RTL2832U 接收棒监听 1090 MHz 广播，并把解码后的航班数据交给调用端。项目不使用 dump1090，不连接在线航班服务，也不显示地图或按距离筛选。

目前仓库包含 Rust 命令行接收程序、供 Swift 调用的 C ABI 动态库接口，以及一个 SwiftUI macOS 桌面面板。WidgetKit 小组件尚未接入。

应用图标资源位于 `YaoguangApp/Assets.xcassets/AppIcon.appiconset`，可通过 `Tools/render_app_icon.swift` 重新生成。版本号、构建号和版权文字集中在 `Config/AppMetadata.xcconfig` 中修改。

## Rust 当前负责的工作

1. 通过 `librtlsdr-rs` 打开 RTL-SDR，并以自动增益接收 1090 MHz、2.4 MS/s 的 IQ 样本。
2. 从 IQ 样本估算每个有效报文的相对信号电平（dBFS），检测 Mode S 前导码并解调 ADS-B 长帧。该值不是经校准的 RSSI 或 SNR。
3. 校验 ADS-B CRC；当前只接受 DF17/DF18 扩展广播帧。
4. 使用 `rs1090` 解码 ADS-B 字段。
5. 将每条有效报文解码为英文结构化更新，通过 C ABI 交给 Swift；Rust 不合并跨报文的飞机状态。
6. 命令行程序会把每条更新打印为英文键名和数值。Rust 不负责中文界面文案或面向用户的单位换算；这些留给 Swift 层。

## Rust / Swift 接口

接口声明位于 `include/yaoguang.h`，动态库导出以下函数：

| 函数 | 用途 |
| --- | --- |
| `yaoguang_start` | 启动后台 RTL-SDR 接收线程并返回不透明句柄 |
| `yaoguang_poll_update` | 非阻塞读取一条 ADS-B 字段更新 |
| `yaoguang_last_error` | 将最近的接收错误复制到调用方提供的缓冲区 |
| `yaoguang_stop` | 停止接收线程并释放句柄 |
| `yaoguang_abi_version` | 返回接口版本，当前为 `3` |

`YaoguangUpdate.fields` 是有效字段位掩码。每个 CRC 有效的 DF17/DF18 报文都会生成一条事件，携带相对信号电平；其他 ADS-B 字段按报文内容提供。Swift 按 `icao24` 合并状态并最多保留十架飞机，按最后收包时间从新到旧排列；有新飞机进入且列表已满时，淘汰最久未更新的飞机及其包数，不因静默超时删除。呼号通过调用方提供的 UTF-8 缓冲区接收，避免 Rust 分配的 `String` 跨越 FFI 边界。

数值单位固定为节、度、英尺、英尺/分钟。速度类型会区分地速和空速，方向会区分地面航迹和磁航向，高度会区分气压高度和 GNSS 高度；信号为整帧平均 IQ 功率相对 ADC 满量程的 dBFS 值，仅作本机接收强弱参考。字段标记和枚举值见 C 头文件。

Apple Silicon 动态库构建命令：

```bash
cargo build --release --target aarch64-apple-darwin --lib
```

输出文件位于 `target/aarch64-apple-darwin/release/libyaoguang_core.dylib`。Swift 调用时包含 `include/yaoguang.h` 并链接此动态库。

## 当前命令行输出

启动后会先报告检测到的调谐器和接收参数。标准错误输出会定期显示扫描位置数和累计 CRC 有效帧数；标准输出会在收到包含已支持字段的报文时打印该报文更新，例如：

```text
780E1F ground_speed_kt=177.00 track_deg=353.00 vertical_rate_fpm=-960
```

字段说明：

| 字段 | 含义 |
| --- | --- |
| `780E1F` | ICAO 24 位航空器地址，以十六进制显示 |
| `callsign` | ADS-B 广播的 Flight ID；可能是航空公司呼号与航班号，也可能是飞机注册号（[FAA Flight ID 说明](https://www.faa.gov/air_traffic/publications/aim_html/chap4_section_5.html)）。只在收到身份报文时输出 |
| `ground_speed_kt` | 地速，单位节（knots） |
| `airspeed_kt` | 空速，单位节 |
| `track_deg` | 地面航迹角，单位度，以真北为 0° 顺时针 |
| `magnetic_heading_deg` | 磁航向，单位度 |
| `barometric_altitude_ft` | 气压高度，单位英尺 |
| `gnss_height_ft` | GNSS 几何高度，单位英尺 |
| `vertical_rate_fpm` | 垂直速度，单位英尺/分钟；正数表示爬升，负数表示下降 |

呼号、速度、方向、高度和垂直速度来自不同类型的 ADS-B 报文，因此每行只包含当前报文实际更新的字段。Swift 层收到这些更新后应按 ICAO 合并成完整航班状态。

## 运行命令行接收程序

需要 macOS、Rust 工具链和已连接且可访问的 RTL2832U 接收棒。Apple Silicon 构建和运行命令：

```bash
cargo run --release --target aarch64-apple-darwin
```

按 `Ctrl-C` 停止接收。

## 项目结构

```text
src/
  main.rs       Rust 命令行入口和英文调试输出
  lib.rs        Rust 库入口
  ffi.rs        C ABI 启停、轮询和错误读取接口
  demod.rs      IQ 幅度/相对信号电平处理、Mode S 前导码检测、帧解调和 CRC 校验
  aircraft.rs   将 ADS-B 报文解码为带有效位的英文结构化更新
include/
  yaoguang.h    Swift/C 调用使用的 ABI 声明
YaoguangApp/
  YaoguangApp.swift          SwiftUI 应用入口
  ReceiverModel.swift        FFI 轮询、最多十架飞机的状态合并与计数
  FlightListView.swift       航班信息表格与接收统计
  Yaoguang.entitlements      App Sandbox 和 USB 访问权限
  Assets.xcassets/           macOS AppIcon 图标资源
Yaoguang.xcodeproj/
  project.pbxproj            macOS 应用构建配置
Config/
  AppMetadata.xcconfig       市场版本、构建号和版权元数据
Tools/
  render_app_icon.swift      生成 AppIcon 的矢量绘制源文件
vendor/
  librtlsdr-rs/ RTL-SDR Rust 驱动依赖的本地补丁版本
```

## 后续方向

- 由主应用把最新航班快照写入 App Group 容器，供独立进程运行的 WidgetKit 扩展读取。
- 增加 WidgetKit 小组件和刷新策略；小组件刷新频率受系统调度。

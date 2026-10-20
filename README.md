# NEU Wi-Fi Auto Login

东北大学校园 Wi-Fi 一键连接与统一身份认证工具，适用于 Windows。

## 功能

- 双击 `Connect.cmd`，自动连接已保存的 `NEU-2.4G`，失败后尝试 `NEU`，随后检查网关并在未在线时认证。
- 登录 Windows 时运行一次连接任务。
- 不进行每两分钟自查，不设置周期性连接任务。
- 密码通过 Windows 当前用户的 DPAPI 加密保存在本机。
- 支持重新设置账号、查看状态和移除自动登录任务。

## 使用条件

- Windows 10/11，已启用 Wi-Fi，位于校园网络覆盖范围。
- 已安装 **64 位 Python 3.12**（含 pip），并可通过 `python --version` 调用。
- 已在 Windows 中保存 `NEU-2.4G` 或 `NEU` 的 Wi-Fi 配置；新电脑需先手动加入一次，以创建网络配置。
- 有效的东北大学统一身份认证账号。

当前版本只适配东北大学认证流程，不支持 `NEU-Mobile` 的接入认证；其他学校需要另行适配。

## 安装与连接

1. 下载整个仓库 ZIP 并解压，保留 `wheels` 文件夹。
2. 双击 `Install.cmd`，在本机输入账号和密码。密码输入时不显示。
3. 安装完成后，双击 `Connect.cmd` 连接网络。可右键该文件创建桌面快捷方式。

安装会使用 `wheels` 中的依赖，无需在线下载 Python 包；Python 解释器本身不在本仓库中。安装后的程序存放在 `%LOCALAPPDATA%\NEU-WiFi-AutoLogin`。

自动任务名称为 `NEU WiFi Auto Login`，仅在当前用户登录 Windows 时触发。若已经连接其他非校园 Wi-Fi，登录任务会跳过；主动运行 `Connect.cmd` 则会尝试切换到校园 Wi-Fi。连接或认证失败后，可查看状态并再次手动运行。

## 更换账号或密码

重新运行 `Install.cmd`，输入新的账号和密码即可更新本机配置。如果当前网关仍处于旧账号在线状态，先在校园网认证页面退出旧账号，再运行 `Connect.cmd`。程序检测到已在线时不会强制替换当前会话。

## 检查与移除

| 文件 | 用途 |
| --- | --- |
| `Install.cmd` | 安装、更新账号或密码 |
| `Connect.cmd` | 连接 Wi-Fi 并检查／完成认证 |
| `Check.cmd` | 查看 Wi-Fi、计划任务及最近日志 |
| `Remove.cmd` | 删除登录任务及保存的账号密码配置 |

`Remove.cmd` 不会删除本地依赖、日志或 Windows 已保存的 Wi-Fi 配置。日志位于 `%LOCALAPPDATA%\NEU-WiFi-AutoLogin\autologin.log`。

## 数据与限制

仓库不包含用户账号、密码、认证票据或运行日志。账号配置保存在本机 `config.json`，其中用户名为明文、密码为 DPAPI 密文。不要将该文件上传到仓库。

认证结果被拒绝时，程序会暂停后续认证；检查账号、密码和网络账户状态后重新运行 `Install.cmd`。学校认证页面、接口或二次验证要求变化后，可能需要更新认证模块。

## 依赖与贡献

统一身份认证由 [NEU-ipgw-manager 3.3](https://pypi.org/project/NEU-ipgw-manager/3.3/) 完成。本项目提供 Windows 安装、Wi-Fi 连接和任务调度脚本，不是学校官方客户端。第三方依赖及其许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 wheel 内的许可文件。

提交问题时请描述 Windows／Python 版本、所连接的 SSID 和错误提示，并去除账号、密码或票据等私人信息。

# BossReminder

A World of Warcraft addon for managing and reminding players about important spell abilities during encounters.

## Features

- **Spell Reminders**: Configure warning and reminder sounds for specific abilities
- **Countdown Voice**: Global countdown voice that plays on timeline highlight events
- **Encounter Integration**: Seamlessly integrates with the Encounter Journal
- **Sound Management**: Uses LibSharedMedia-3.0 for flexible sound selection
- **Import/Export**: Save and share your configurations with other players
- **Overview Panel**: Centralized management of all spell configurations

## Installation

1. Extract the addon folder to your WoW Interface\AddOns directory
2. Make sure LibSharedMedia-3.0, AceGUI-3.0, and other dependencies are installed
3. Restart World of Warcraft
4. Enable the addon in the Add-ons menu

## Usage

- Click the minimap icon to open the Overview panel
- Use the Encounter Journal config button (C) on boss abilities to configure sounds
- Set a global countdown voice in the Overview panel
- Export/Import configurations to share with teammates

## Acknowledgments

Special thanks to **JSUI** for providing the foundational concepts and design ideas that inspired this addon's development.

## Disclaimer

I am not proficient in Lua and have limited familiarity with the WoW API. If there are any errors or issues in this code, I welcome your corrections and feedback. Please feel free to report bugs or suggest improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Dependencies

- LibSharedMedia-3.0
- AceGUI-3.0
- AceLocale-3.0
- LibDBIcon-1.0
- CallbackHandler-1.0

---

# 首领提醒 (BossReminder)

一个用于管理和提醒玩家在副本遭遇期间重要法术能力的魔兽世界插件。

## 功能特性

- **法术提醒**: 为特定能力配置警告和提醒语音
- **倒数语音**: 全局倒数语音，在时间轴高亮事件时播放
- **遭遇整合**: 与遭遇手册无缝集成
- **音频管理**: 使用 LibSharedMedia-3.0 实现灵活的音频选择
- **导入/导出**: 保存并与其他玩家分享您的配置
- **概览面板**: 集中管理所有法术配置

## 安装说明

1. 将插件文件夹解压到 WoW Interface\AddOns 目录
2. 确保已安装 LibSharedMedia-3.0、AceGUI-3.0 等依赖项
3. 重启魔兽世界
4. 在插件菜单中启用该插件

## 使用方法

- 点击小地图图标打开概览面板
- 使用遭遇手册中Boss能力旁的配置按钮 (C) 来配置语音
- 在概览面板中设置全局倒数语音
- 导入/导出配置与小队成员分享

## 特别感谢

特别感谢 **JSUI** 提供的基础概念和设计思路，这些灵感启发了本插件的开发。

## 免责声明

本人不擅长 Lua 语言，对 WoW API 也比较生疏。如果代码中存在任何错误或问题，欢迎指正和反馈。请随时报告问题或提出改进建议。

## 许可证

本项目采用 MIT 许可证 - 详见 LICENSE 文件。

## 依赖项

- LibSharedMedia-3.0
- AceGUI-3.0
- AceLocale-3.0
- LibDBIcon-1.0
- CallbackHandler-1.0

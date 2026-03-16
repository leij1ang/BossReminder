## C_EncounterWarnings 使用说明（BossReminder 摘要）

### 1. 功能概览

`C_EncounterWarnings` 对应“系统级首领警报”的默认策略，按 **severity（严重等级）** 提供：

- 推荐颜色
- 推荐 SoundKit 音效
- 是否在当前版本 / 设置中可用
- 按严重等级直接播放系统警报音

它不关心具体的 `encounterEventID`，而是与 `C_EncounterEvents` 互补，提供“按严重度分级”的默认行为。

---

### 2. 功能开关

- **`C_EncounterWarnings.IsFeatureAvailable() → isAvailable`**
  - 功能是否在当前客户端存在（版本 / 场景支持）。

- **`C_EncounterWarnings.IsFeatureEnabled() → isAvailableAndEnabled`**
  - 功能存在且已在系统设置中启用。

> 在使用该模块的声音或颜色前，可以先检查这两个开关，以避免在不支持的环境下调用。

---

### 3. 按严重等级获取颜色与声音

- **`C_EncounterWarnings.GetColorForSeverity(severity) → color`**
  - 输入：`severity`（常与 `C_EncounterEvents.GetEventInfo` 返回的 `info.severity` 对应）。
  - 返回：推荐颜色，一般为 `{ r, g, b, a }`。
  - 用途示例：
    - 某个事件自身没有颜色时，根据严重等级选用一个合适的默认色；
    - 在自定义 UI 中，对不同严重等级统一配色。

- **`C_EncounterWarnings.GetSoundKitForSeverity(severity) → soundKitID`**
  - 输入：`severity`。
  - 返回：系统推荐的 soundKit ID。
  - 用途示例：
    - 当未配置自定义语音时，用系统默认的严重级别音效作为 fallback；
    - 在自定义系统中，将该 soundKit 封装成 EncounterEvents 的 `sound` table：
      ```lua
      { soundKitID = C_EncounterWarnings.GetSoundKitForSeverity(severity), channel = "Master" }
      ```

---

### 4. 播放系统默认警报音

- **`C_EncounterWarnings.PlaySound(severity) → soundHandle`**
  - 直接按严重等级播放系统配置的警报音，不修改任何 Encounter 配置。
  - 典型用途：
    - UI 中提供“试听系统默认警报”的按钮；
    - 在尚未为某个事件配置自定义声音时，作为简单的发声手段。

- **`C_EncounterWarnings.GetEditModeWarningInfo(severity) → warningInfo`**
  - 主要服务于 Edit Mode 界面，返回 UI 配置相关信息。
  - 一般插件无需直接依赖。

---

### 5. 与 BossReminder 的关系（可选用法）

- BossReminder 目前只直接操作 `C_EncounterEvents`，对 `severity` 主要做展示。
- 将来可以考虑：
  - 当 `GetEventSound(eventID, trigger)` 为空时，根据 `info.severity` 选择：
    - 调用 `C_EncounterWarnings.PlaySound(info.severity)` 作为 fallback；
    - 或从 `GetSoundKitForSeverity(info.severity)` 构造一个 `sound` table，并写回 `SetEventSound`。
  - 当某些事件没有自定义颜色时，用 `GetColorForSeverity(info.severity)` 做默认色。


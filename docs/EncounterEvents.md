## C_EncounterEvents 使用说明（BossReminder 摘要）

### 1. 功能概览

`C_EncounterEvents` 用于按 **encounterEventID** 管理首领时间线事件，包括：

- 获取事件列表与事件详情
- 读取 / 设置事件颜色
- 读取 / 设置 / 播放事件声音（按 trigger 区分）

BossReminder 中：

- `BossReminder_DB:ScanAllEvents` 使用它构建 `eventCache` 与 `spellEventMap`
- `BossReminder_Tools` 使用它展示所有事件及其颜色 / 严重等级 / 声音
- `BossReminder_Sound` 使用它根据 spell 配置或清除事件声音

---

### 2. 事件列表与基础信息

- **`C_EncounterEvents.GetEventList() → encounterEventIDs`**
  - 返回：所有 `encounterEventID` 的数组。
  - 用途：遍历事件做扫描 / 构建缓存。

- **`C_EncounterEvents.HasEventInfo(encounterEventID) → exists`**
  - 返回：布尔值，是否存在可用信息。
  - 建议：在 `GetEventInfo` 之前先调用，避免无效 ID。

- **`C_EncounterEvents.GetEventInfo(encounterEventID) → encounterEventInfo`**
  - 返回：事件信息结构体，字段以实测为准，常见字段包括：
    - `spellID` / `severity` / `enabled`
    - `iconFileID` / `icons`
    - `color`
  - BossReminder 用法：
    - `eventCache[eventID] = info`
    - 若 `info.spellID` 存在，则更新 `spellEventMap[spellID] = eventID`

---

### 3. 事件颜色

- **`C_EncounterEvents.GetEventColor(encounterEventID) → color`**
  - 返回：当前颜色，一般为 `{ r, g, b, a }`。

- **`C_EncounterEvents.SetEventColor(encounterEventID [, color])`**
  - `color` 省略或为 `nil`：清除该事件的自定义颜色。
  - 传入 `color` table：为该事件设置自定义颜色。

---

### 4. 事件声音（按 trigger）

- **`C_EncounterEvents.GetEventSound(encounterEventID, trigger) → sound?`**
  - `trigger`：使用 `Enum.EncounterEventSoundTrigger`（枚举），例如：
    - `OnTimelineEventFinished`（BossReminder 用作 Warning）
    - `OnTimelineEventHighlight`（BossReminder 用作 Highlight / 倒数）
  - 返回：
    - `sound` table 或 `nil`，实测常见字段：
      - `file`：自定义声音文件路径
      - `soundKitID`：内置 sound kit ID
      - `channel`：音量通道（如 `"Master"`）
      - `volume`：音量（可选）

- **`C_EncounterEvents.SetEventSound(encounterEventID, trigger [, sound])`**
  - `sound == nil` 或未提供：清除该事件在该 trigger 下的自定义声音。
  - `sound` 为 table：设置自定义声音。
  - BossReminder 典型格式：
    ```lua
    { file = path, channel = "Master", volume = 1 }
    ```

- **`C_EncounterEvents.PlayEventSound(encounterEventID, trigger) → handle`**
  - 语义：按当前配置播放一次该事件在该 trigger 下的声音，不修改任何配置。
  - 在 BossReminder Tools 中：
    - Warning / Highlight / S2 按钮优先调用 `PlayEventSound` 进行预览；
    - 若失败，再回退到 `PlaySoundFile` / `PlaySound`。

---

### 5. BossReminder 中的推荐用法（简要）

- **扫描阶段**：  
  使用 `GetEventList` + `HasEventInfo` + `GetEventInfo` 构建只读缓存 `eventCache`，并建立 `spellEventMap`。

- **配置阶段（按 spell）**：  
  高层逻辑基于 `spellID` 决定要不要有声音，最后通过 `GetEventIDBySpellID(spellID)` 找到 `eventID`，再调用：
  - `SetEventSound(eventID, TRIGGER_WARNING, soundTable)`
  - `SetEventSound(eventID, TRIGGER_HIGHLIGHT, soundTable或nil)`

- **调试 / 预览阶段**：  
  Tools 界面从 `eventCache` 读取事件字段，用：
  - `GetEventSound(eventID, trigger)` 展示当前绑定的声音；
  - `PlayEventSound(eventID, trigger)` 直接试听实际效果。


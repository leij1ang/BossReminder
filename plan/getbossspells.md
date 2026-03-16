1. 获取当前赛季
2. 获取当前赛季所有的地下城/团本的id(我可能维护一下赛季与instanceid的表格)
3. 根据id获取boss
4. 点击boss获取boss的技能
5. 与缓存中的event进行对比,如果存在则显示,不存在则跳过
6. 点击技能时绘制config ui,根据trigger有三个声音选择,同时在trigger.OnTimelineEventHighlight增加一个播放倒计时的选择

团本/地下城需要展示为两个不同的tab,如浏览器顶部的页签,看下附件图,先复述一下整体界面

我准备不要config和overview,统一使用一个界面来维护了

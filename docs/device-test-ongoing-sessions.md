# Device test checklist — calls, meeting rooms and recordings that keep going

Run on a real phone after the next build (Android and iPhone). Native parts (Android `NxOngoingService`,
Picture-in-Picture, iOS CallKit for meeting rooms) compile in CI but can only be checked on a device.

## Floating bubble (in the app)
- [ ] Meeting room: open a room, press back / "ย่อ" → the room keeps going, a bubble shows (timer, mic).
- [ ] Tap the bubble → back in the same room (no new join, captions / chat keep their history).
- [ ] Drag the bubble: it snaps to the nearest side.
- [ ] Drag the bubble onto the × at the bottom → it hides; a pill "กำลังประชุม · แสดง" at the top brings it back.
- [ ] Long-press the bubble → menu (room: mic / back / leave; call: mic / open / hang up; recordings: pause / open).
- [ ] Only one bubble at a time: call > room > meeting recording > notebook recording.
- [ ] Meeting detail page / Minutes Home / Home card "กำลังทำอยู่" show "กลับเข้าห้อง" while minimised.

## Notification bar (Android)
- [ ] Team call connected → ongoing notification with the clock, ปิดไมค์ ⇄ เปิดไมค์, วางสาย, เปิด.
- [ ] Meeting room → same notification (ออกจากห้อง, กลับเข้าห้อง); buttons work with the app in the background.
- [ ] Screen off for 5 minutes during a call / room / recording → audio keeps going.
- [ ] Meeting recording notification says "กำลังบันทึกประชุม" (notebook: "กำลังบันทึกเสียง").
- [ ] Video call / room with camera on, press Home → Picture-in-Picture with the speaker; tap → back in the app.
- [ ] Swipe the app away → notifications disappear.

## iPhone
- [ ] Meeting room shows as a call (green pill / lock screen); mute and end from the call screen work on the room.
- [ ] Team calls still use CallKit as before; a room and a call do not mix up mute / end.
- [ ] Recording keeps going with the screen locked (red indicator).

## Business switch / sign-out
- [ ] Switch business while recording → the sheet warns; the recording finishes into the old business.
- [ ] Sign out during a room / call / recording → the room is left, the call ends, the last parts upload.

## Permissions / sharing
- [ ] A role without "AI Assistant" does not see it (menu and /ai link); owner / admin always do.
- [ ] Minutes shared with me open read only (no share / summarise / tasks / edit, Ask disabled).
- [ ] "แชร์กับฉัน" filter and badge; a share sends a bell + push that opens the meeting (switching business).

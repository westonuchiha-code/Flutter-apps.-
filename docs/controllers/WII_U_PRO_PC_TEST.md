# Wii U Pro on the PC: the 5-minute test

Goal: see whether SDL's own Wii U Pro driver works on your PC over Bluetooth. If it does, the
Wii U Pro becomes a real, named controller ("Nintendo Wii U Pro Controller") in everything that
uses SDL: the PC XMB (Godot 4.7), RetroArch, PCSX2, RPCS3, and Controller Lab.

## 1. Turn on SDL's Wii driver (once)
1. Press Start, type **environment**, open **Edit environment variables for your account**.
2. Under *User variables*, click **New...**
   - Variable name: `SDL_JOYSTICK_HIDAPI_WII`
   - Variable value: `1`
3. OK, OK. Programs that are already open don't see it until they're restarted.

(To undo: delete that variable.)

## 2. Pair the Wii U Pro (once)
1. Settings > **Bluetooth & devices** > **Add device** > **Bluetooth**.
2. Press the small red **SYNC** button on the back of the Wii U Pro (the lights start running).
3. Pick **Nintendo RVL-CNT-01-UC** in the list.
   - If Windows asks for a PIN, choose to pair without one / skip.
   - Windows may say "Driver error" or show no buttons in its own settings: that's normal,
     SDL talks to it directly.

## 3. Try it
- **Controller Lab** (`controller_lab-latest` release, Windows zip): it lists every controller the
  way SDL sees it. You should see "Nintendo Wii U Pro Controller"; open it and every button lights
  up on the drawing. Controller Lab turns SDL's Wii driver on for itself, so it works even before
  step 1 (the other programs need step 1).
- **RetroArch**: Settings > Drivers > **Controller** = `sdl2` (restart RetroArch), then
  Settings > Input > Port 1 Controls: the device should read Nintendo Wii U Pro Controller.
- **The PC XMB**: restart it and move around the menu with the Wii U Pro.
- **PCSX2**: Settings > Controllers: the SDL source should list it.

## 4. Tell Claude what happened
- Works everywhere: great, Controller Lab builds on SDL for it.
- Pairs but nothing sees it: say which programs, and whether its lights keep running or settle
  on one. That decides whether Controller Lab needs to read it itself.
- Won't pair: your PC's Bluetooth may not like Nintendo controllers; a cheap Bluetooth 5.0 USB
  dongle usually fixes that.

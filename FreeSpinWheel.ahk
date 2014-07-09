#SingleInstance Force
#MaxHotkeysPerInterval 500

SetBatchLines, -1
SetWinDelay, 0
SetControlDelay, 0

CoordMode, Mouse, Screen
CoordMode, ToolTip, Screen

; タスクトレイメニューの設定
Menu, Tray, NoStandard
Menu, Tray, Add, 設定ファイル編集, EditIniFile
Menu, Tray, Add, 再起動, Reload
Menu, Tray, Add, 終了, ExitApp

; iniファイルから設定の読み込み
iniFileDefault := A_ScriptDir . "\FreeSpinWheel.ini.default"
iniFile := A_ScriptDir . "\FreeSpinWheel.ini"
if (!FileExist(iniFile)) {
    FileCopy, %iniFileDefault%, %iniFile%
}
IniRead, strokeTimeout , %iniFile%, FreeSpinWheel, StrokestrokeTimeout , 100
IniRead, acceleration, %iniFile%, FreeSpinWheel, Acceleration, 1.30
IniRead, deceleration, %iniFile%, FreeSpinWheel, Deceleration, 0.70
IniRead, maxSpeed, %iniFile%, FreeSpinWheel, MaxSpeed, 300
IniRead, minSpeed, %iniFile%, FreeSpinWheel, MinSpeed, 5
IniRead, nonStopModeStroke, %iniFile%, FreeSpinWheel, NonStopModeStroke, 0
IniRead, stopByMouseMove, %iniFile%, FreeSpinWheel, StopByMouseMove, on
IniRead, stopByLButton, %iniFile%, FreeSpinWheel, StopByLButton, off
IniRead, stopByRButton, %iniFile%, FreeSpinWheel, StopByRButton, off
IniRead, stopByMButton, %iniFile%, FreeSpinWheel, StopByMButton, off
IniRead, animationIcon, %iniFile%, FreeSpinWheel, AnimationIcon, off
IniRead, showTooltip, %iniFile%, FreeSpinWheel, ShowTooltip, off
IniRead, reverse, %iniFile%, FreeSpinWheel, Reverse, off
stopByMouseMove := (stopByMouseMove = "on")
stopByLButton := (stopByLButton = "on")
stopByRButton := (stopByRButton = "on")
stopByMButton := (stopByMButton = "on")
animationIcon := (animationIcon = "on")
showTooltip := (showTooltip = "on")
reverse := (reverse = "on")

; スクロールと減速用のタイマーの起動
SetTimer, ScrollTimer, 10
SetTimer, DecelerateTimer, 100

; アイコン表示用ウィンドウ
if (animationIcon) {
    Gui, +LastFound +AlwaysOnTop +ToolWindow -Caption +E0x02080020
    Gui, Add, Picture, X0 Y0 Vicon, %A_ScriptDir%\spin.png
    WinSet, Transparent, 196
    WinSet, Region, E W48 H48 0-0
    Gui, Show, W196 H48 Hide
    SetTimer, IconTimer, 10
}

; ツールチップの表示
if (showTooltip) {
    SetTimer, TooltipTimer, 100
}
Exit

; ホイール回転時の処理
*WheelUp::WheelSpined(wheelUpHist, 1)
*WheelDown::WheelSpined(wheelDownHist, -1)

; 左ボタンによるスクロール停止
#if (stopByLButton && speed)
*LButton::Stop()

; 右ボタンによるスクロール停止
#if (stopByRButton && speed)
*RButton::Stop()

; 中ボタンによるスクロール停止
#if (stopByMButton && speed)
*MButton::Stop()

; 設定ファイル編集
EditIniFile:
    Run, %iniFile%
    return

; 再起動
Reload:
    Reload
    return

; 終了
ExitApp:
    ExitApp

; スクロール用タイマー
ScrollTimer:
    if (speed || line) {
        Scroll()
    }
    return

; 減速用タイマーー
DecelerateTimer:
    if (speed || line) {
        Decelerate()
    }
    return

; アイコン表示用タイマー
IconTimer:
    if (animationIcon) {
        if (speed) {
            f++
            f := Mod(f, 4)
            pos := -f * 48
            Gui, +LastFound
            Gui, Color, % (nonStopModeStroke && nonStopModeStroke <= stroke) ? "FF0000" : "666666"
            GuiControl, MoveDraw, icon, X%pos% Y0
            WinMove, x, y
            if (!animationIconShown) {
                Gui, Show, NA
                animationIconShown := true
            }
        } else {
            if (animationIconShown) {
                Gui, +LastFound
                Gui, Show, Hide
                animationIconShown := false
            }
        }
    }
    return

; ツールチップ表示用タイマー
TooltipTimer:
    if (showTooltip && (speed || tooltipText)) {
        if (speed) {
            tooltipText := 0 < speed ? "▲" : "▼"
            tooltipText .= "[stroke:" stroke "]"
            tooltipText .= "[speed:" Ceil(Abs(speed)) "]"
        } else {
            tooltipText := ""
        }
        Tooltip, %tooltipText%
    }
    return

; ホイール回転時の処理
WheelSpined(ByRef wheelHist, sign) {
    global speed, line, ctrl, x, y
    if (speed * sign < 0) {
        Stop()
    } else {
        line += sign
        GetSpinSpeed(wheelHist, sign)
        GetControl(ctrl, x, y)
        Scroll()
    }
}

; 回転速度を求める
GetSpinSpeed(ByRef wheelHist, sign) {
    global strokeTimeout, maxSpeed, stroke, speed, acceleration
    tickCount := A_TickCount, newHist := tickCount
    stroke := 1, time := 0
    Loop, PARSE, wheelHist, CSV
    {
        if (tickCount - A_LoopField <= strokeTimeout) {
            stroke++
            time += tickCount - A_LoopField
            tickCount := A_LoopField
            newHist .= "," . tickCount
        } else {
            break
        }
    }
    wheelHist := newHist
    if (stroke == 1) {
        speed := 0
    } else {
        speed := stroke / time * 1000
        speed *= acceleration ** (stroke - 1)
        speed := speed < maxSpeed ? speed : maxSpeed
        speed *= sign
    }
}

; スクロール
Scroll() {
    global speed, line, ctrl, x, y, stopByMouseMove, reverse
    static tickCount
    elapsed := tickCount ? (A_TickCount - tickCount) : 1
    tickCount := A_TickCount
    prevX := x, prevY := y
    GetControl(ctrl, x, y)
    if (stopByMouseMove && (25 < (x - prevX) ** 2 + (y - prevY) ** 2)) {
        Stop()
    } else {
        line += elapsed * speed / 1000
        notch := line < 0 ? Ceil(line) : Floor(line)
        line -= notch
        if (notch) {
            wheelMax := notch < 0 ? -273 : 273
            loop Abs(notch / wheelMax)
            {
                PostMouseWheel(ctrl, wheelMax, x, y, reverse)
            }
            notch := Mod(notch, wheelMax)
            PostMouseWheel(ctrl, notch, x, y, reverse)
        }
    }
}

; 減速
Decelerate() {
    global stroke, speed, line, deceleration, minSpeed, nonStopModeStroke
    if (nonStopModeStroke == 0 || stroke < nonStopModeStroke) {
        speed *= 1 - deceleration ** (stroke - 1)
        if (Abs(line) < 1 && Abs(speed) < minSpeed) {
            Stop()
        }
    }
}

; 停止
Stop() {
    global stroke, speed, line
    stroke := speed := line := 0
}

; マウスポインタ位置のコントロールを取得
GetControl(ByRef ctrl, ByRef x, ByRef y) {
    MouseGetPos, x, y, win, ctrl, 3
    if (ctrl) {
        lParam := (x & 0xFFFF) | (y & 0xFFFF) << 16
        SendMessage, 0x84, 0, lParam,, ahk_id %ctrl%
        if (ErrorLevel == 0xFFFFFFFF) {
            MouseGetPos,,,, ctrl, 2
        }
    }
    ctrl := ctrl ? ctrl : win
}

; コントロールにWM_MOUSEWHEELを投げる
PostMouseWheel(ctrl, notch, x, y, reverse=false) {
    delta := (reverse ? -notch : notch) * 120
    wParam := GetKeyState("LButton")
            | GetKeyState("RButton") << 1
            | GetKeyState("Shift") << 2
            | GetKeyState("Ctrl") << 3
            | GetKeyState("MButton") << 4
            | GetKeyState("XButton1") << 5
            | GetKeyState("XButton2") << 6
            | (delta & 0xFFFF) << 16
    lParam := (x & 0xFFFF) | (y & 0xFFFF) << 16
    PostMessage, 0x20A, wParam, lParam,, ahk_id %ctrl%
}

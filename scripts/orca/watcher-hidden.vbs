' Khoi chay orca-layout-watcher.ps1 that su AN.
'
' Vi sao can file nay: Scheduled Task goi thang
'   powershell.exe -WindowStyle Hidden -File ...
' van hien mot cua so console luc dang nhap, vi Windows Terminal dang la terminal
' mac dinh va no bo qua -WindowStyle. Da gap that: cua so
' "Administrator: ...powershell.exe" bat luc khoi dong va khong bao gio tat.
'
' WScript.Shell.Run voi tham so cua so = 0 tao tien trinh an han, khong phu thuoc
' terminal mac dinh.

Option Explicit

Dim sh, fso, here, ps1, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = fso.BuildPath(here, "orca-layout-watcher.ps1")

If Not fso.FileExists(ps1) Then
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"

' 0 = cua so an, False = khong cho tien trinh ket thuc
sh.Run cmd, 0, False

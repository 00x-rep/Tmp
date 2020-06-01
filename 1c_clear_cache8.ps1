Remove-Item $env:AppData\1C\1CEStart\ibases.v8i -Force
Get-ChildItem "$env:HOMEPATH\AppData\Roaming\1C\1cv8\*","$env:HOMEPATH\AppData\Local\1C\1cv8\*"  | Where {$_.Name -as [guid]} | Remove-Item -Force -Recurse
#Get-ChildItem "$env:HOMEPATH\AppData\Local\1C\1Cv82\*","$env:HOMEPATH\AppData\Roaming\1C\1Cv82\*" | Where {$_.Name -as [guid]} | Remove-Item -Force -Recurse

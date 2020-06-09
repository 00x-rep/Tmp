# Script ps-backup-files
<#

Скрипт для архивирования файлов из каталога Source в каталог Dest с помощью архиватора 7z.
Варианты архивирования: полное, дифференциальное, инкрементальное. Файлы сравниваются по пути и хешу.
Если полного архивирования еще не было, то оно выполняется.

БД скопированных файлов хранится в файле CopiedFiles.csv в каталоге WorkFolder.

Удаление устаревших бэкапов выполняется в день полного бэкапа, при этом cоздается лог удаления
бэкапов в файл $DelOldBackupLog.
В переменных $GoogDiffIncFiles и $GoodFullFiles указываем, сколько недель храним бэкапы

В процессе своей работы скрипт создает временные файлы ListFiles2AddArc и 7zLastLog в каталоге WorkFolder
для работы 7z, которые удаляются после успешной архивации.

В переменную 7z необходимо добавить путь до 7z.exe


USAGE:	.\ps-backup-files.ps1
			-Source [path to source folder]
			-Dest [path to destination folder]
			-WorkFolder [path to work folder]
			-CopyType [type of backup: Full, Inc, Diff]
            -DoW4Full [Full backup day: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday

#>

param(

  [Parameter(Mandatory=$true, Position=0)]
  [ValidateScript({Test-Path $_})]
  [String]$Source,

  [Parameter(Mandatory=$true, Position=1)]
  [ValidateScript({Test-Path $_})]
  [String]$Dest,

  [Parameter(Mandatory=$true, Position=2)]
  [ValidateScript({Test-Path $_})]
  [String]$WorkingFolder,

  [Parameter(Mandatory=$true, Position=3)]
  [ValidateSet('Full','Inc','Diff')]
  [String]$CopyType,

  [Parameter(Mandatory=$true, Position=4)]
  [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
  [String]$DoW4Full
  
)


### Объявление переменных ###

#$WorkingFolder = 'D:\Scripts\Backup\IncBackup'                      # Рабочий каталог, где создаются логи и временные файлы
#$Source = 'D:\1'                                                    # Что архивируем
#$Dest = 'D:\2'                                                      # Куда архивируем
$DBCopiedFiles = $WorkingFolder + '\' + 'CopiedFiles.csv'            # БД скопированных файлов
$ListFiles2AddArc = $WorkingFolder + '\' + 'ListFiles2AddArc.txt'    # Файлы для добавления в архив
$7z = 'd:\Util\Arc\7-Zip\7z.exe'                                     # Архиватор
$7zLastLog = $WorkingFolder + '\' + '7zLastLog.txt'                  # Лог работы архиватора, создается если будет ошибка при архивировании
#$DoW4Full = 'Monday'                                                # День недели, когда делаем полный бэкап.
                                                                     # Дни недели: 1..7|ForEach{(Get-Date -Day $_).DayOfWeek}
#$CopyType = 'Inc'                                                   # Тип копирования: Full, Inc, Diff
$NameOfArchive = $Dest + '\' + $env:computername + '-' + (Get-Date -format "yyyyMMdd-HHmm") + '-' + $CopyType + '.7z'    # Имя архива
$DelOldBackupLog = $WorkingFolder + '\' + 'DelOldBackupLog.txt'      # Лог удаления старых бэкапов
$GoogDiffIncFiles = 4                                                # Сколько недель храним Diff и Inc файлы
$GoodFullFiles = 8                                                   # Сколько недель храним Full файлы
#Mail
$smtpserver = 'smtp.mail.ru'                                         # SMTP сервер
$email = '----------@mail.ru'                                        # Кому отправляем сообщение об ошибках
$SubjectText = "There was an error during backup operation on $env:COMPUTERNAME"       # Тема сообщения
$TextMessage = "There was an error during backup operation on $env:COMPUTERNAME. <br/>Failed with exit code $LASTEXITCODE and $?"       # Текст сообщения
$from = "$env:COMPUTERNAME<$env:COMPUTERNAME@$env:USERDOMAIN>"       # От кого
if ($env:COMPUTERNAME -eq $env:USERDOMAIN) {$from = "$env:COMPUTERNAME<$env:COMPUTERNAME@$env:USERDOMAIN.local>"}         # Если комп не в домене, добавим .local


### Объявление функций ###

# Сравнение файлов в источнике с уже скопированными файлами
function Compare-Files {
   param(

        [parameter(Mandatory=$TRUE,Position=0)]
        $Source,

        [parameter(Mandatory=$TRUE,Position=1)]
        $DBCopiedFiles

   )

   process {

    # Считываем файлы источника с хешем
    $CurrFiles = Get-ChildItem –Path $Source -Recurse | Get-FileHash -Algorithm MD5 | select Path, Hash
    # Если ничего еще не копировали, будем копировать все файлы
    if (!(Test-Path -Path $DBCopiedFiles)) 
            {
            $Files2Copy = $CurrFiles
            }
    # Берем файлы из источника и сравниваем их с уже скопированными по путям и хешам
    else {
    $CopiedFiles = Import-Csv $DBCopiedFiles
    foreach ($fileCurrFiles in $CurrFiles)
            {
            $found = $false
                foreach ($fileCopiedFiles in $CopiedFiles)
                        {
                        if ($fileCurrFiles.Hash -eq $fileCopiedFiles.Hash -And $fileCurrFiles.Path -eq $fileCopiedFiles.Path)
                         {
                         $found = $true
                         }
                        }
            # Если файла нет в скопированных, добавляем его в $Files2Copy для копирования
            if ((!$found) -and ($fileCurrFiles -ne ""))
                 {
                 [array]$Files2Copy += $fileCurrFiles
                 }
            }
        }    
    return $Files2Copy        
    }

}


# Архивирование файлов
function Add-Files-to-Archive {
   param(

        [parameter(Mandatory=$TRUE,Position=0)]
        $Files2Copy,

        [parameter(Mandatory=$TRUE,Position=1)]
        $NameOfArchive

   )

   process {

        # Если есть что архивировать, запускаем процесс архивирования
        If ($Files2Copy.count -gt 0) {
        # Создаем список файлов для архивации
        $Files2Copy.Path | Out-File -Encoding utf8 $ListFiles2AddArc -Force
        # Аргументы для 7Zip
        $7zArgs =  @(
	                "a";                         # Создаем архив
	                "-t7z";                      # Формат 7z
	                "-mx=7";                     # Максимальный уровень компрессии
                    "-spf2";                     # Полные пути к файлам. -spf - с диском
                    "$NameOfArchive";            # Имя архива (*.7z файл)
                    "-i@$ListFiles2AddArc";      # Файлы для добавление к архиву
                    )
        # Запуск архивирования
        & $7z @7zArgs | Tee-Object -LiteralPath $7zLastLog

                                     }
           }
}


# Список полных бэкапов на этой неделе
function Get-Last-Full-Backup {
   param(

        [parameter(Mandatory=$TRUE,Position=0)]
        $DoW4Full,

        [parameter(Mandatory=$TRUE,Position=1)]
        $Dest
   )

   process {

        # Дата, когда должен был быть полный бекап на этой нделе
        $n = 0
        do {
            $LastFullBackupDay = (date -Hour 0 -Minute 0 -Second 0).AddDays(-$n)
            $n++
        }
        Until ( $LastFullBackupDay.DayOfWeek -eq $DoW4Full )

        $LastFullBackupFiles = Get-ChildItem –Path $Dest -File -Filter $env:COMPUTERNAME-*-Full.7z | Where-Object ({$_.LastWriteTime -ge $LastFullBackupDay})

        # $LastFullBackupDay - дата последнего полного бэкапа
        # $LastFullBackupFiles - файл(ы) последнего полного бэкапа

    return $LastFullBackupFiles

   }
}


# Удаление устаревших бэкапов
function Del-Old-Backup {
   param(

        [parameter(Mandatory=$TRUE,Position=0)]
        $DelOldBackupLog,

        [parameter(Mandatory=$TRUE,Position=1)]
        $GoogDiffIncFiles,

        [parameter(Mandatory=$TRUE,Position=2)]
        $GoodFullFiles

   )

   process {

    $DelOldDiffIncFiles = Get-ChildItem –Path $Dest -File -Filter $env:COMPUTERNAME-*-*.7z | Where-Object ({$_.LastWriteTime -lt (date -Hour 0 -Minute 0 -Second 0).AddDays(-($GoogDiffIncFiles*7))}) | ? {$_.Name -like "*Diff.7z" -or $_.Name -like "*Inc.7z"}
    $DelOldFullFiles = Get-ChildItem –Path $Dest -File -Filter $env:COMPUTERNAME-*-Full.7z | Where-Object ({$_.LastWriteTime -lt (date -Hour 0 -Minute 0 -Second 0).AddDays(-($GoodFullFiles*7))})

    # Если есть, что удалять, пишем лог и удаляем
    If ($DelOldDiffIncFiles -or $DelOldFullFiles)
        {
            date >> $DelOldBackupLog
            $DelOldDiffIncFiles | ft Name, LastWriteTime >> $DelOldBackupLog
            $DelOldFullFiles  | ft Name, LastWriteTime >> $DelOldBackupLog

            $DelOldDiffIncFiles | Remove-Item -Force -ErrorAction SilentlyContinue
            $DelOldFullFiles | Remove-Item -Force -ErrorAction SilentlyContinue

        }

   }
}



### Основная логика программы ###

# Если раньше не делали архивирование, то делаем полное (есть файл $DBCopiedFiles?)
if (!(Test-Path -Path $DBCopiedFiles)) {$CopyType = 'Full'}

# Если тип бэкапа = Full или если не нашли полный бэкап за эту неделю
# устанавливаем тип бэкапа в Full и делаем полный бэкап
# Для создания полного бэкапа надо удалить файл с БД скопированных файлов - $DBCopiedFiles
# В день полного бэкапа ($DoW4Full = 'Sunday') делаем полный бэкап 1 раз
$FBF = Get-Last-Full-Backup $DoW4Full $Dest
if (($CopyType -eq 'Full') -or (!$FBF) -or (((Get-Date).DayOfWeek -eq $DoW4Full) -and (!$FBF))) {
    $CopyType = 'Full'
    Remove-Item $DBCopiedFiles -Force -ErrorAction SilentlyContinue
}


# Если условия сработали переназначим имя файла
$NameOfArchive = $Dest + '\' + $env:computername + '-' + (Get-Date -format "yyyyMMdd-HHmm") + '-' + $CopyType + '.7z'    # Имя архива

# Сравнение файлов в источнике с уже скопированными файлами
[array]$Files2Copy = Compare-Files $Source $DBCopiedFiles

# Если есть что архивировать, запускаем процесс архивирования
If ($Files2Copy.count -gt 0) {

        # Начало архивирования
        Add-Files-to-Archive $Files2Copy $NameOfArchive
        If (($CopyType -eq 'Full') -or ($CopyType -eq 'Inc'))
            {
            # Если архивация прошла без ошибок и если тип бэкапа Full или Inc,
            # то добавляем скопированные файлы в БД скопированных файлов
            if ($LASTEXITCODE -eq 0)
                {
                # Добавляем в $DBCopiedFiles скопированные файлы
                $Files2Copy | Select-Object -Property Path, Hash | Export-Csv -NoTypeInformation -Path $DBCopiedFiles -Append -Encoding UTF8
                }
            }
}


# Проверяем ошибки архивирования
if (($? -eq $false) -or ($LASTEXITCODE -gt 0))
        {
	        Write-Host "Failed with exit code $LASTEXITCODE and $?"
            Send-MailMessage -To $email -From $from -Subject $SubjectText -smtpserver $smtpserver -Body $TextMessage -BodyAsHtml
        }
Else    {
            # Если архивация прошла успешно, удаляем файл с файлами для архивации и лог работы 7zip
            Start-Sleep -Milliseconds 500 # Если задержки нет, то файл $7zLastLog оказывается заблокированным
            Remove-Item $ListFiles2AddArc, $7zLastLog -Force -ErrorAction SilentlyContinue

            # В день полного бэкапа ($DoW4Full = 'Sunday') удаляем устаревшие бэкапы
            if ((Get-Date).DayOfWeek -eq $DoW4Full)
                    {
                    Del-Old-Backup $DelOldBackupLog $GoogDiffIncFiles $GoodFullFiles
                    }
        }



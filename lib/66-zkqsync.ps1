# 紫孔雀配置同步（独立模块）
# 设计约束：
#   1) 不改现有看护/采集/休眠逻辑；同步期间只临时阻止自动恢复和自动休眠。
#   2) 不写 config.json；页面状态、备份、日志、临时状态全部放在 DataDir 自己的文件里。
#   3) 同步在独立后台 Job 里跑，UI 只读状态文件，不阻塞界面。
#   4) 只允许「运行中的实例」作为源和目标；关机和休眠实例明确跳过。

$script:zkqSyncState = @{
    Running       = $false
    Job           = $null
    Source        = ''
    Selected      = @{}
    Initialized   = $false
    ControlsBound = $false
    LastStatus    = $null
    LastLogText   = ''
}

$script:zkqSyncStatusFile = ''
$script:zkqSyncLogFile = ''
$script:zkqSyncBackupDir = ''
$script:zkqSyncCancelFile = ''
$script:zkqSyncAdb = ''
$script:zkqSyncWorkerSb = $null
$script:zkqSyncBusy = $false
$script:zkqSyncBusyTargets = @()

# ------------------------------------------------------------------ 初始化
function Initialize-ZkqSyncRuntime {
    param([string]$DataDir, [string]$AdbExe)
    if (-not $DataDir) { return }
    $script:zkqSyncAdb = "$AdbExe"
    $script:zkqSyncStatusFile = Join-Path $DataDir 'zkq-sync-status.json'
    $script:zkqSyncLogFile = Join-Path (Join-Path $DataDir 'logs') 'zkq-sync.log'
    $script:zkqSyncBackupDir = Join-Path $DataDir 'backup\zkq-sync'
    $script:zkqSyncCancelFile = Join-Path $DataDir 'zkq-sync-cancel.flag'
    if (-not $script:zkqSyncState) {
        $script:zkqSyncState = @{
            Running = $false; Job = $null; Source = ''; Selected = @{}
            Initialized = $false; ControlsBound = $false; LastStatus = $null; LastLogText = ''
        }
    }
}

function Get-ZkqSyncWorker {
    if ($script:zkqSyncWorkerSb) { return $script:zkqSyncWorkerSb }
    $b64 = 'cGFyYW0oCiAgICBbc3RyaW5nXSRBZGJFeGUsCiAgICBbc3RyaW5nXSRTb3VyY2VJbmRleCwKICAgIFtzdHJpbmddJFNvdXJjZVNlcmlhbCwKICAgIFtzdHJpbmddJFRhcmdldHNKc29uLAogICAgW3N0cmluZ10kUmVtb3RlUGF0aCwKICAgIFtzdHJpbmddJEJhY2t1cERpciwKICAgIFtzdHJpbmddJExvZ0ZpbGUsCiAgICBbc3RyaW5nXSRTdGF0dXNGaWxlLAogICAgW3N0cmluZ10kQ2FuY2VsRmlsZSwKICAgIFtib29sXSRSZXN0YXJ0QXBwLAogICAgW2Jvb2xdJEJhY2t1cAopCgokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ0NvbnRpbnVlJwokUGFja2FnZSA9ICdjb20uY29jLnprcWNvZGUnCnRyeSB7IFtDb25zb2xlXTo6T3V0cHV0RW5jb2RpbmcgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4IH0gY2F0Y2ggeyB9Cgokc3RhdHVzID0gW29yZGVyZWRdQHsKICAgIFJ1bm5pbmcgICAgPSAkdHJ1ZQogICAgRG9uZSAgICAgICA9ICRmYWxzZQogICAgQ2FuY2VsbGVkICA9ICRmYWxzZQogICAgU3RhdGUgICAgICA9ICdydW5uaW5nJwogICAgTWVzc2FnZSAgICA9ICflh4blpIflkIzmraUnCiAgICBTb3VyY2UgICAgID0gIiRTb3VyY2VJbmRleCIKICAgIFRvdGFsICAgICAgPSAwCiAgICBDb21wbGV0ZWQgID0gMAogICAgU3VjY2VzcyAgICA9IDAKICAgIEZhaWwgICAgICAgPSAwCiAgICBTa2lwICAgICAgID0gMAogICAgU3RhcnRlZEF0ICA9IChHZXQtRGF0ZSkuVG9TdHJpbmcoJ3l5eXktTU0tZGQgSEg6bW06c3MnKQogICAgRmluaXNoZWRBdCA9ICcnCiAgICBMb2cgICAgICAgID0gQCgpCiAgICBSZXN1bHRzICAgID0gQCgpCn0KCmZ1bmN0aW9uIFNhdmUtU3RhdHVzIHsKICAgIHRyeSB7CiAgICAgICAgJGRpciA9IFNwbGl0LVBhdGggLVBhcmVudCAkU3RhdHVzRmlsZQogICAgICAgIGlmICgkZGlyIC1hbmQgLW5vdCAoVGVzdC1QYXRoICRkaXIpKSB7IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJGRpciAtRm9yY2UgfCBPdXQtTnVsbCB9CiAgICAgICAgJHRtcCA9ICIkU3RhdHVzRmlsZS50bXAiCiAgICAgICAgKCRzdGF0dXMgfCBDb252ZXJ0VG8tSnNvbiAtRGVwdGggNikgfCBTZXQtQ29udGVudCAtUGF0aCAkdG1wIC1FbmNvZGluZyBVVEY4CiAgICAgICAgTW92ZS1JdGVtIC1QYXRoICR0bXAgLURlc3RpbmF0aW9uICRTdGF0dXNGaWxlIC1Gb3JjZQogICAgfSBjYXRjaCB7IH0KfQoKZnVuY3Rpb24gQWRkLUxvZyhbc3RyaW5nXSRtc2cpIHsKICAgICRsaW5lID0gJ1t7MDpISDptbTpzc31dIHsxfScgLWYgKEdldC1EYXRlKSwgJG1zZwogICAgJHN0YXR1cy5Mb2cgPSBAKCRzdGF0dXMuTG9nICsgJGxpbmUpCiAgICB0cnkgewogICAgICAgICRkaXIgPSBTcGxpdC1QYXRoIC1QYXJlbnQgJExvZ0ZpbGUKICAgICAgICBpZiAoJGRpciAtYW5kIC1ub3QgKFRlc3QtUGF0aCAkZGlyKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRkaXIgLUZvcmNlIHwgT3V0LU51bGwgfQogICAgICAgIEFkZC1Db250ZW50IC1QYXRoICRMb2dGaWxlIC1WYWx1ZSAoJ1t7MDp5eXl5LU1NLWRkIEhIOm1tOnNzfV0gezF9JyAtZiAoR2V0LURhdGUpLCAkbXNnKSAtRW5jb2RpbmcgVVRGOAogICAgfSBjYXRjaCB7IH0KICAgIFNhdmUtU3RhdHVzCn0KCmZ1bmN0aW9uIEludm9rZS1BZGIgewogICAgcGFyYW0oW3N0cmluZ10kU2VyaWFsLCBbc3RyaW5nW11dJEFkYkFyZ3MpCiAgICB0cnkgeyByZXR1cm4gKCYgJEFkYkV4ZSAtcyAkU2VyaWFsIEBBZGJBcmdzIDI+JjEgfCBPdXQtU3RyaW5nKSB9IGNhdGNoIHsgcmV0dXJuICcnIH0KfQoKZnVuY3Rpb24gR2V0LUFkYk1kNSB7CiAgICBwYXJhbShbc3RyaW5nXSRTZXJpYWwpCiAgICAkb3V0ID0gSW52b2tlLUFkYiAtU2VyaWFsICRTZXJpYWwgLUFkYkFyZ3MgQCgnc2hlbGwnLCAnbWQ1c3VtJywgJFJlbW90ZVBhdGgpCiAgICBpZiAoJG91dCAtbWF0Y2ggJyg/aSlcYihbMC05YS1mXXszMn0pXGInKSB7IHJldHVybiAkTWF0Y2hlc1sxXS5Ub0xvd2VyKCkgfQogICAgcmV0dXJuICcnCn0KCmZ1bmN0aW9uIEZpbmlzaChbc3RyaW5nXSRzdGF0ZSwgW3N0cmluZ10kbWVzc2FnZSkgewogICAgJHN0YXR1cy5SdW5uaW5nID0gJGZhbHNlCiAgICAkc3RhdHVzLkRvbmUgPSAkdHJ1ZQogICAgJHN0YXR1cy5TdGF0ZSA9ICRzdGF0ZQogICAgJHN0YXR1cy5NZXNzYWdlID0gJG1lc3NhZ2UKICAgICRzdGF0dXMuRmluaXNoZWRBdCA9IChHZXQtRGF0ZSkuVG9TdHJpbmcoJ3l5eXktTU0tZGQgSEg6bW06c3MnKQogICAgU2F2ZS1TdGF0dXMKfQoKdHJ5IHsKICAgICR0bXAgPSBKb2luLVBhdGggKFtTeXN0ZW0uSU8uUGF0aF06OkdldFRlbXBQYXRoKCkpICgnemtxc3luYy0nICsgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJHRtcCAtRm9yY2UgfCBPdXQtTnVsbAogICAgJHNyY0xvY2FsID0gSm9pbi1QYXRoICR0bXAgJ3prcV9jb25maWcuanNvbicKCiAgICAkdGFyZ2V0cyA9IEB7fQogICAgdHJ5IHsKICAgICAgICAkb2JqID0gJFRhcmdldHNKc29uIHwgQ29udmVydEZyb20tSnNvbgogICAgICAgIGZvcmVhY2ggKCRwIGluICRvYmouUFNPYmplY3QuUHJvcGVydGllcykgeyAkdGFyZ2V0c1siJCgkcC5OYW1lKSJdID0gIiQoJHAuVmFsdWUpIiB9CiAgICB9IGNhdGNoIHsgfQogICAgJHN0YXR1cy5Ub3RhbCA9ICR0YXJnZXRzLkNvdW50CgogICAgQWRkLUxvZyAoJ+W8gOWni+WQjOatpe+8mua6kOWunuS+iyB7MH0g4oaSIHsxfSDkuKrnm67moIcnIC1mICRTb3VyY2VJbmRleCwgJHRhcmdldHMuQ291bnQpCiAgICBpZiAoLW5vdCAkU291cmNlU2VyaWFsKSB7CiAgICAgICAgQWRkLUxvZyAn5rqQ5a6e5L6L5rKh5pyJIGFkYiDluo/liJflj7fvvIzml6Dms5Xor7vlj5bphY3nva4nCiAgICAgICAgRmluaXNoICdlcnJvcicgJ+a6kOWunuS+i+S4jeWPr+eUqCcKICAgICAgICByZXR1cm4KICAgIH0KICAgIGlmICgtbm90ICR0YXJnZXRzIC1vciAkdGFyZ2V0cy5Db3VudCAtZXEgMCkgewogICAgICAgIEFkZC1Mb2cgJ+ayoeacieebruagh+WunuS+iycKICAgICAgICBGaW5pc2ggJ2Vycm9yJyAn5rKh5pyJ55uu5qCH5a6e5L6LJwogICAgICAgIHJldHVybgogICAgfQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkQmFja3VwRGlyKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRCYWNrdXBEaXIgLUZvcmNlIHwgT3V0LU51bGwgfQoKICAgIHRyeSB7ICRudWxsID0gJiAkQWRiRXhlIGNvbm5lY3QgJFNvdXJjZVNlcmlhbCAyPiYxIH0gY2F0Y2ggeyB9CiAgICAkcHVsbE91dCA9ICgmICRBZGJFeGUgLXMgJFNvdXJjZVNlcmlhbCBwdWxsICRSZW1vdGVQYXRoICRzcmNMb2NhbCAyPiYxIHwgT3V0LVN0cmluZykKICAgIGlmICgtbm90IChUZXN0LVBhdGggJHNyY0xvY2FsKSAtb3IgKEdldC1JdGVtICRzcmNMb2NhbCkuTGVuZ3RoIC1sdCAyKSB7CiAgICAgICAgQWRkLUxvZyAoJ+ivu+WPlua6kOmFjee9ruWksei0pe+8mnswfScgLWYgKCRwdWxsT3V0LlRyaW0oKSkpCiAgICAgICAgRmluaXNoICdlcnJvcicgJ+ivu+WPlua6kOmFjee9ruWksei0pScKICAgICAgICByZXR1cm4KICAgIH0KICAgICRzcmNIYXNoID0gKEdldC1GaWxlSGFzaCAtUGF0aCAkc3JjTG9jYWwgLUFsZ29yaXRobSBNRDUpLkhhc2guVG9Mb3dlcigpCiAgICBBZGQtTG9nICgn5rqQ6YWN572u5aSn5bCPIHswfSDlrZfoioLvvIxNRDUgezF9JyAtZiAoR2V0LUl0ZW0gJHNyY0xvY2FsKS5MZW5ndGgsICRzcmNIYXNoKQoKICAgICRzdGFtcCA9IEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXlNTWRkLUhIbW1zcycKICAgIGZvcmVhY2ggKCRpZHggaW4gQCgkdGFyZ2V0cy5LZXlzIHwgU29ydC1PYmplY3QgeyBbaW50XSgkXyAtcmVwbGFjZSAnW15cZF0nLCAnMCcpIH0pKSB7CiAgICAgICAgaWYgKFRlc3QtUGF0aCAkQ2FuY2VsRmlsZSkgewogICAgICAgICAgICAkc3RhdHVzLkNhbmNlbGxlZCA9ICR0cnVlCiAgICAgICAgICAgIEFkZC1Mb2cgJ+eUqOaIt+WBnOatou+8jOW3suS4reaWrScKICAgICAgICAgICAgYnJlYWsKICAgICAgICB9CiAgICAgICAgJHNlcmlhbCA9ICIkKCR0YXJnZXRzWyRpZHhdKSIKICAgICAgICAkc3RhdHVzLkNvbXBsZXRlZCsrCiAgICAgICAgaWYgKC1ub3QgJHNlcmlhbCkgewogICAgICAgICAgICAkc3RhdHVzLkZhaWwrKwogICAgICAgICAgICAkc3RhdHVzLlJlc3VsdHMgPSBAKCRzdGF0dXMuUmVzdWx0cyArIFtwc2N1c3RvbW9iamVjdF1AeyBJbmRleCA9ICIkaWR4IjsgT2sgPSAkZmFsc2U7IE1lc3NhZ2UgPSAn5rKh5pyJIGFkYiDluo/liJflj7cnIH0pCiAgICAgICAgICAgIEFkZC1Mb2cgKCflrp7kvosgezB977ya5rKh5pyJIGFkYiDluo/liJflj7fvvIzot7Pov4cnIC1mICRpZHgpCiAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgfQoKICAgICAgICBBZGQtTG9nICgn5a6e5L6LIHswfe+8muWHhuWkh+WQjOatpScgLWYgJGlkeCkKICAgICAgICB0cnkgeyAkbnVsbCA9ICYgJEFkYkV4ZSBjb25uZWN0ICRzZXJpYWwgMj4mMSB9IGNhdGNoIHsgfQoKICAgICAgICBpZiAoJEJhY2t1cCkgewogICAgICAgICAgICAkYmsgPSBKb2luLVBhdGggJEJhY2t1cERpciAoIuWunuS+i3swfS17MX0uanNvbiIgLWYgJGlkeCwgJHN0YW1wKQogICAgICAgICAgICAkYmtPdXQgPSAoJiAkQWRiRXhlIC1zICRzZXJpYWwgcHVsbCAkUmVtb3RlUGF0aCAkYmsgMj4mMSB8IE91dC1TdHJpbmcpCiAgICAgICAgICAgIGlmIChUZXN0LVBhdGggJGJrKSB7CiAgICAgICAgICAgICAgICBBZGQtTG9nICgn5a6e5L6LIHswfe+8muWOn+mFjee9ruW3suWkh+S7veWIsCB7MX0nIC1mICRpZHgsICRiaykKICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgIEFkZC1Mb2cgKCflrp7kvosgezB977ya5Y6f6YWN572u5LiN5a2Y5Zyo5oiW5aSH5Lu95aSx6LSl77yIezF977yJJyAtZiAkaWR4LCAkYmtPdXQuVHJpbSgpKQogICAgICAgICAgICB9CiAgICAgICAgfQoKICAgICAgICAkbnVsbCA9IEludm9rZS1BZGIgLVNlcmlhbCAkc2VyaWFsIC1BZGJBcmdzIEAoJ3NoZWxsJywgJ2FtJywgJ2ZvcmNlLXN0b3AnLCAkUGFja2FnZSkKICAgICAgICAkcHVzaE91dCA9IEludm9rZS1BZGIgLVNlcmlhbCAkc2VyaWFsIC1BZGJBcmdzIEAoJ3B1c2gnLCAkc3JjTG9jYWwsICRSZW1vdGVQYXRoKQogICAgICAgICRkZXZIYXNoID0gR2V0LUFkYk1kNSAtU2VyaWFsICRzZXJpYWwKICAgICAgICBpZiAoJGRldkhhc2ggLW5lICRzcmNIYXNoKSB7CiAgICAgICAgICAgIEFkZC1Mb2cgKCflrp7kvosgezB977ya6aaW5qyh5qCh6aqM5LiN5LiA6Ie077yM6YeN5o6o5LiA5qyhJyAtZiAkaWR4KQogICAgICAgICAgICAkbnVsbCA9IEludm9rZS1BZGIgLVNlcmlhbCAkc2VyaWFsIC1BZGJBcmdzIEAoJ3NoZWxsJywgJ2FtJywgJ2ZvcmNlLXN0b3AnLCAkUGFja2FnZSkKICAgICAgICAgICAgJHB1c2hPdXQgPSBJbnZva2UtQWRiIC1TZXJpYWwgJHNlcmlhbCAtQWRiQXJncyBAKCdwdXNoJywgJHNyY0xvY2FsLCAkUmVtb3RlUGF0aCkKICAgICAgICAgICAgJGRldkhhc2ggPSBHZXQtQWRiTWQ1IC1TZXJpYWwgJHNlcmlhbAogICAgICAgIH0KCiAgICAgICAgaWYgKCRkZXZIYXNoIC1lcSAkc3JjSGFzaCkgewogICAgICAgICAgICAkc3RhdHVzLlN1Y2Nlc3MrKwogICAgICAgICAgICAkbXNnID0gJ+W3suWQjOatpScKICAgICAgICAgICAgaWYgKCRSZXN0YXJ0QXBwKSB7CiAgICAgICAgICAgICAgICAkbnVsbCA9IEludm9rZS1BZGIgLVNlcmlhbCAkc2VyaWFsIC1BZGJBcmdzIEAoJ3NoZWxsJywgJ21vbmtleScsICctcCcsICRQYWNrYWdlLCAnLWMnLCAnYW5kcm9pZC5pbnRlbnQuY2F0ZWdvcnkuTEFVTkNIRVInLCAnMScpCiAgICAgICAgICAgICAgICBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDcwMAogICAgICAgICAgICAgICAgJG1zZyA9ICflt7LlkIzmraXvvIzntKvlrZTpm4Dlt7Lph43lkK8nCiAgICAgICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgICAgICAkbXNnID0gJ+W3suWQjOatpe+8jOe0q+WtlOmbgOS/neaMgeWBnOatoicKICAgICAgICAgICAgfQogICAgICAgICAgICAkc3RhdHVzLlJlc3VsdHMgPSBAKCRzdGF0dXMuUmVzdWx0cyArIFtwc2N1c3RvbW9iamVjdF1AeyBJbmRleCA9ICIkaWR4IjsgT2sgPSAkdHJ1ZTsgTWVzc2FnZSA9ICRtc2cgfSkKICAgICAgICAgICAgQWRkLUxvZyAoJ+WunuS+iyB7MH3vvJp7MX0nIC1mICRpZHgsICRtc2cpCiAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgJHN0YXR1cy5GYWlsKysKICAgICAgICAgICAgJHN0YXR1cy5SZXN1bHRzID0gQCgkc3RhdHVzLlJlc3VsdHMgKyBbcHNjdXN0b21vYmplY3RdQHsgSW5kZXggPSAiJGlkeCI7IE9rID0gJGZhbHNlOyBNZXNzYWdlID0gJ01ENSDmoKHpqozlpLHotKUnIH0pCiAgICAgICAgICAgIEFkZC1Mb2cgKCflrp7kvosgezB977yaTUQ1IOagoemqjOWksei0pe+8iOiuvuWkhyB7MX3vvIzmnKzlnLAgezJ977yJJyAtZiAkaWR4LCAkZGV2SGFzaCwgJHNyY0hhc2gpCiAgICAgICAgfQogICAgfQoKICAgICRyZXN1bHRUZXh0ID0gKCfmiJDlip8gezB977yM5aSx6LSlIHsxfe+8jOi3s+i/hyB7Mn0nIC1mICRzdGF0dXMuU3VjY2VzcywgJHN0YXR1cy5GYWlsLCAkc3RhdHVzLlNraXApCiAgICBpZiAoJHN0YXR1cy5DYW5jZWxsZWQpIHsgRmluaXNoICdjYW5jZWxsZWQnICgn5bey5YGc5q2i77yaJyArICRyZXN1bHRUZXh0KSB9CiAgICBlbHNlaWYgKCRzdGF0dXMuRmFpbCAtZ3QgMCkgeyBGaW5pc2ggJ2Vycm9yJyAkcmVzdWx0VGV4dCB9CiAgICBlbHNlIHsgRmluaXNoICdkb25lJyAkcmVzdWx0VGV4dCB9CiAgICBBZGQtTG9nICgn5ZCM5q2l57uT5p2f77yaJyArICRyZXN1bHRUZXh0KQp9IGNhdGNoIHsKICAgIEFkZC1Mb2cgKCflkIzmraXlvILluLjvvJonICsgJF8uRXhjZXB0aW9uLk1lc3NhZ2UpCiAgICBGaW5pc2ggJ2Vycm9yJyAoJ+W8guW4uO+8micgKyAkXy5FeGNlcHRpb24uTWVzc2FnZSkKfSBmaW5hbGx5IHsKICAgIHRyeSB7IGlmICgkdG1wIC1hbmQgKFRlc3QtUGF0aCAkdG1wKSkgeyBSZW1vdmUtSXRlbSAkdG1wIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9IH0gY2F0Y2ggeyB9Cn0='
    $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    $script:zkqSyncWorkerSb = [scriptblock]::Create($text)
    return $script:zkqSyncWorkerSb
}

# ------------------------------------------------------------------ 页面小工具
function New-ZkqSyncChip {
    param([string]$Text, [string]$Sub, [bool]$Active, [scriptblock]$OnClick)
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = [System.Windows.CornerRadius]::new(9)
    $b.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
    $b.Margin = New-Object System.Windows.Thickness(0, 0, 8, 8)
    $b.BorderThickness = 1
    $b.Cursor = 'Hand'
    if ($Active) {
        $b.Background = Brush '#2410B981'
        $b.BorderBrush = Brush '#6610B981'
    } else {
        $b.Background = Brush '#12FFFFFF'
        $b.BorderBrush = Brush '#22FFFFFF'
    }
    $sp = New-Object System.Windows.Controls.StackPanel
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = 11.5
    $t.FontWeight = $(if ($Active) { 'SemiBold' } else { 'Normal' })
    $t.Foreground = Brush '#F2F2F5'
    $s = New-Object System.Windows.Controls.TextBlock
    $s.Text = $Sub
    $s.FontSize = 9.5
    $s.Foreground = Brush '#9E9EA6'
    $s.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$sp.Children.Add($t)
    [void]$sp.Children.Add($s)
    $b.Child = $sp
    if ($OnClick) { $b.Add_MouseLeftButtonUp($OnClick) }
    return $b
}

function Set-ZkqSyncSource([string]$Index) {
    $script:zkqSyncState.Source = "$Index"
    $script:zkqSyncState.Initialized = $false
    Render-ShellSync
}

function Set-ZkqSyncSelection([string]$Index, [bool]$On) {
    if (-not $script:zkqSyncState.Selected) { $script:zkqSyncState.Selected = @{} }
    $script:zkqSyncState.Selected["$Index"] = $On
}

function Get-ZkqSyncRunningRows {
    $rows = @(Get-ShellRows)
    return @($rows | Where-Object {
        $_.Online -eq $true -and -not ($_.PSObject.Properties.Name -contains 'WakeAt' -and $_.WakeAt)
    } | Sort-Object { [int]("$($_.Index)" -replace '[^\d]', '0') })
}

function Update-ZkqSyncButtons {
    $win = $script:shellWin
    if (-not $win) { return }
    $running = [bool]$script:zkqSyncState.Running
    $start = $win.FindName('BtnSyncStart')
    $st = $win.FindName('TxtSyncStart')
    $cancel = $win.FindName('BtnSyncCancel')
    $refresh = $win.FindName('BtnSyncRefresh')
    if ($start) {
        $start.Opacity = $(if ($running) { 0.45 } else { 1 })
        $start.Cursor = $(if ($running) { 'Arrow' } else { 'Hand' })
        $start.Background = Brush $(if ($running) { '#18FFFFFF' } else { '#2E10B981' })
    }
    if ($st) { $st.Text = $(if ($running) { '同步中…' } else { '开始同步' }) }
    if ($cancel) {
        $cancel.Opacity = $(if ($running) { 1 } else { 0.4 })
        $cancel.Cursor = $(if ($running) { 'Hand' } else { 'Arrow' })
    }
    if ($refresh) { $refresh.Opacity = $(if ($running) { 0.4 } else { 1 }) }
}

# ------------------------------------------------------------------ 构建页面
function Reset-ZkqSyncPage {
    $win = $script:shellWin
    if (-not $win) { return }
    if (-not $script:zkqSyncStatusFile) { Initialize-ZkqSyncRuntime -DataDir $DataDir -AdbExe $AdbExe }

    $rows = @(Get-ShellRows)
    $run = @(Get-ZkqSyncRunningRows)
    $srcPnl = $win.FindName('PnlSyncSources')
    $tgtPnl = $win.FindName('PnlSyncTargets')

    # 源实例：保留当前选择，失效则取第一个运行中的实例
    $src = "$($script:zkqSyncState.Source)"
    if (-not ($run | Where-Object { "$($_.Index)" -eq $src })) {
        $src = $(if ($run.Count -gt 0) { "$($run[0].Index)" } else { '' })
        $script:zkqSyncState.Source = $src
    }

    if ($srcPnl) {
        $srcPnl.Children.Clear()
        if ($run.Count -eq 0) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = '没有运行中的实例。请先在「实例管理」启动一个实例并打开紫孔雀。'
            $tb.FontSize = 10.5
            $tb.Foreground = Brush '#9E9EA6'
            $tb.TextWrapping = 'Wrap'
            $tb.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
            [void]$srcPnl.Children.Add($tb)
        } else {
            foreach ($r in $run) {
                $idx = "$($r.Index)"
                $nm = "$($r.Name)"
                $sub = "实例 $idx" + $(if ("$($r.Judge)" -eq '运行中' -or "$($r.Judge)" -eq '正常') { ' · 运行中' } else { " · $($r.Judge)" })
                $on = ($idx -eq $src)
                $click = { Set-ZkqSyncSource $idx }.GetNewClosure()
                [void]$srcPnl.Children.Add((New-ZkqSyncChip -Text $nm -Sub $sub -Active $on -OnClick $click))
            }
        }
    }

    # 目标：保留用户勾选，新出现的运行中实例默认勾选
    if ($tgtPnl) {
        $tgtPnl.Children.Clear()
        $runIdx = @{}
        foreach ($r in $run) { $runIdx["$($r.Index)"] = $true }
        $sel = $script:zkqSyncState.Selected
        if (-not $sel) { $sel = @{}; $script:zkqSyncState.Selected = $sel }

        $any = $false
        foreach ($r in $rows) {
            $idx = "$($r.Index)"
            if ($idx -eq $src) { continue }
            $isRun = $false
            try { $isRun = ($r.Online -eq $true -and -not ($r.PSObject.Properties.Name -contains 'WakeAt' -and $r.WakeAt)) } catch { }
            $any = $true
            if (-not $sel.ContainsKey($idx)) { $sel[$idx] = $isRun }

            $cb = New-Object System.Windows.Controls.CheckBox
            $nm = "$($r.Name)"
            $suffix = $(if ($isRun) { '' } else { '（未启动，跳过）' })
            $cb.Content = "$nm  ·  实例$idx$suffix"
            $cb.FontSize = 11.2
            $cb.Foreground = Brush $(if ($isRun) { '#E6E6EC' } else { '#6E6E78' })
            $cb.Margin = New-Object System.Windows.Thickness(0, 3, 0, 3)
            $cb.IsEnabled = $isRun
            $cb.IsChecked = [bool]$sel[$idx]
            if ($isRun) {
                $i2 = $idx
                $cb.Add_Checked({ Set-ZkqSyncSelection $i2 $true }.GetNewClosure())
                $cb.Add_Unchecked({ Set-ZkqSyncSelection $i2 $false }.GetNewClosure())
            }
            [void]$tgtPnl.Children.Add($cb)
        }

        if (-not $any -or $rows.Count -le 1) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = '没有其他实例可同步。'
            $tb.FontSize = 10.5
            $tb.Foreground = Brush '#9E9EA6'
            $tb.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
            [void]$tgtPnl.Children.Add($tb)
        }
    }

    # 控件事件只绑一次
    if (-not $script:zkqSyncState.ControlsBound) {
        $refresh = $win.FindName('BtnSyncRefresh')
        if ($refresh) { $refresh.Add_MouseLeftButtonUp({ $script:zkqSyncState.Initialized = $false; Render-ShellSync }) }
        $start = $win.FindName('BtnSyncStart')
        if ($start) { $start.Add_MouseLeftButtonUp({ try { Start-ZkqSync } catch { Write-Diag "同步启动异常: $($_.Exception.Message)" } }) }
        $cancel = $win.FindName('BtnSyncCancel')
        if ($cancel) { $cancel.Add_MouseLeftButtonUp({ try { Stop-ZkqSync } catch { } }) }
        $script:zkqSyncState.ControlsBound = $true
    }

    $script:zkqSyncState.Initialized = $true
    Update-ZkqSyncStatus
}

# ------------------------------------------------------------------ 状态刷新
function Update-ZkqSyncStatus {
    $win = $script:shellWin
    if (-not $win) { return }
    $state = $script:zkqSyncState
    if (-not $state) { return }

    $status = $null
    if ($script:zkqSyncStatusFile -and (Test-Path $script:zkqSyncStatusFile)) {
        try {
            $raw = Get-Content $script:zkqSyncStatusFile -Raw -Encoding UTF8
            if ($raw) { $status = $raw | ConvertFrom-Json }
        } catch { $status = $null }
    }
    if ($status) { $state.LastStatus = $status }

    $running = [bool]$state.Running
    if ($status -and $status.Running -eq $false -and $status.Done -eq $true) {
        $running = $false
    }
    if ($status -and $status.Running -eq $true) { $running = $true }
    $state.Running = $running

    $t = $win.FindName('TxtSyncStatus')
    $log = $win.FindName('TxtSyncLog')
    if ($t) {
        if ($status) {
            $msg = "$($status.Message)"
            if ($running) { $msg = ('同步中：{0}  {1}/{2}' -f $msg, $status.Completed, $status.Total) }
            elseif ("$($status.State)" -eq 'done') { $msg = '完成：' + $msg }
            elseif ("$($status.State)" -eq 'cancelled') { $msg = '已停止：' + $msg }
            elseif ("$($status.State)" -eq 'error') { $msg = '失败：' + $msg }
            $t.Text = $msg
            $t.Foreground = Brush $(if ("$($status.State)" -eq 'error') { '#FF8078' } elseif ("$($status.State)" -eq 'done') { '#34C759' } else { '#9E9EA6' })
        } elseif ($running) {
            $t.Text = '同步中…'
        }
    }
    if ($log -and $status -and $status.Log) {
        $lines = @($status.Log)
        if ($lines.Count -gt 160) { $lines = $lines[($lines.Count - 160)..($lines.Count - 1)] }
        $txt = ($lines -join "`r`n")
        if ($txt -ne $state.LastLogText) {
            $log.Text = $txt
            $state.LastLogText = $txt
        }
    }

    Update-ZkqSyncButtons

    if (-not $running) {
        $script:zkqSyncBusy = $false
        $script:zkqSyncBusyTargets = @()
        if ($state.Job) {
            try {
                $j = $state.Job
                if ($j.State -in @('Completed', 'Failed', 'Stopped')) {
                    Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
                    $state.Job = $null
                }
            } catch { }
        }
    }
}

function Render-ShellSync {
    try {
        if (-not $script:zkqSyncStatusFile) { Initialize-ZkqSyncRuntime -DataDir $DataDir -AdbExe $AdbExe }
        if (-not $script:zkqSyncState.Initialized) { Reset-ZkqSyncPage }
        else { Update-ZkqSyncStatus }
    } catch {
        Write-Diag ("配置同步页面异常: " + $_.Exception.Message)
    }
}

# ------------------------------------------------------------------ 启停
function Start-ZkqSync {
    $state = $script:zkqSyncState
    if (-not $state -or $state.Running) { return }
    $win = $script:shellWin
    if (-not $win) { return }
    if (-not $script:zkqSyncStatusFile) { Initialize-ZkqSyncRuntime -DataDir $DataDir -AdbExe $AdbExe }
    if (-not $script:zkqSyncAdb -or -not (Test-Path $script:zkqSyncAdb)) {
        $t = $win.FindName('TxtSyncStatus'); if ($t) { $t.Text = '找不到 adb.exe，无法同步'; $t.Foreground = Brush '#FF8078' }
        return
    }

    $rows = @(Get-ShellRows)
    $selected = @($state.Selected.Keys | Where-Object { $state.Selected[$_] -eq $true })
    $plan = Get-ZkqSyncPlan -Instances $rows -Source "$($state.Source)" -Selected $selected
    if (-not $plan.Ok) {
        $t = $win.FindName('TxtSyncStatus'); if ($t) { $t.Text = $plan.Message; $t.Foreground = Brush '#FF8078' }
        return
    }

    $srcSerial = Get-DeviceSerial "$($plan.Source.Index)"
    if (-not $srcSerial) {
        $t = $win.FindName('TxtSyncStatus'); if ($t) { $t.Text = '源实例没有 adb 序列号（请确认已启动并连上 adb）'; $t.Foreground = Brush '#FF8078' }
        return
    }
    $serialMap = @{}
    foreach ($p in @($plan.Targets)) {
        $s = Get-DeviceSerial "$($p.Index)"
        if (-not $s) {
            $t = $win.FindName('TxtSyncStatus'); if ($t) { $t.Text = "实例$($p.Index) 没有 adb 序列号，请稍后刷新重试"; $t.Foreground = Brush '#FF8078' }
            return
        }
        $serialMap["$($p.Index)"] = "$s"
    }

    $chkBackup = $win.FindName('ChkSyncBackup')
    $chkRestart = $win.FindName('ChkSyncRestart')
    $doBackup = $true
    $doRestart = $true
    try { if ($chkBackup) { $doBackup = [bool]$chkBackup.IsChecked } } catch { }
    try { if ($chkRestart) { $doRestart = [bool]$chkRestart.IsChecked } } catch { }

    # 覆盖第三方配置文件前必须二次确认
    $confirmText = @(
        '将把实例 {0} 的紫孔雀配置覆盖到 {1} 个目标实例：' -f $plan.Source.Index, @($plan.Targets).Count
        ''
        ($plan.Targets | ForEach-Object { '  · 实例 {0} {1}' -f $_.Index, $_.Name }) -join "`r`n"
        ''
        $(if ($doBackup) { '覆盖前会备份目标实例原配置。' } else { '未开启备份，覆盖后无法从面板恢复。' })
        $(if ($doRestart) { '同步后会强制停止并重新启动目标实例的紫孔雀。' } else { '同步后会强制停止紫孔雀，并保持停止。' })
        ''
        '确定继续？'
    ) -join "`r`n"
    try {
        $answer = [System.Windows.MessageBox]::Show($confirmText, '确认同步紫孔雀配置', 'YesNo', 'Question')
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    } catch { }

    try {
        if (Test-Path $script:zkqSyncCancelFile) { Remove-Item $script:zkqSyncCancelFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $script:zkqSyncStatusFile) { Remove-Item $script:zkqSyncStatusFile -Force -ErrorAction SilentlyContinue }
        if (-not (Test-Path $script:zkqSyncBackupDir)) { New-Item -ItemType Directory -Path $script:zkqSyncBackupDir -Force | Out-Null }
        $sb = Get-ZkqSyncWorker
        $job = Start-Job -ScriptBlock $sb -ArgumentList @(
            $script:zkqSyncAdb,
            "$($plan.Source.Index)",
            "$srcSerial",
            ($serialMap | ConvertTo-Json -Compress),
            '/sdcard/zkqFiles/zkq_config.json',
            $script:zkqSyncBackupDir,
            $script:zkqSyncLogFile,
            $script:zkqSyncStatusFile,
            $script:zkqSyncCancelFile,
            $doRestart,
            $doBackup
        )
        $state.Job = $job
        $state.Running = $true
        $state.LastLogText = ''
        $script:zkqSyncBusy = $true
        $script:zkqSyncBusyTargets = @($serialMap.Keys | ForEach-Object { "$_" })
        # 立刻显示一个初始状态，避免 Job 首次写文件前的空白
        $t = $win.FindName('TxtSyncStatus'); if ($t) { $t.Text = '同步中：准备读取源配置'; $t.Foreground = Brush '#9E9EA6' }
        $log = $win.FindName('TxtSyncLog'); if ($log) { $log.Text = '正在启动后台同步…' }
        Update-ZkqSyncButtons
        Write-Diag ("配置同步: 源实例 {0} -> {1} 个目标，备份={2} 重启={3}" -f $plan.Source.Index, $serialMap.Count, $doBackup, $doRestart)
    } catch {
        $state.Running = $false
        $script:zkqSyncBusy = $false
        $script:zkqSyncBusyTargets = @()
        $t = $win.FindName('TxtSyncStatus'); if ($t) { $t.Text = ('启动失败：' + $_.Exception.Message); $t.Foreground = Brush '#FF8078' }
        Write-Diag ('配置同步启动失败: ' + $_.Exception.Message)
        Update-ZkqSyncButtons
    }
}

function Stop-ZkqSync {
    $state = $script:zkqSyncState
    if (-not $state -or -not $state.Running) { return }
    try {
        [System.IO.File]::WriteAllText($script:zkqSyncCancelFile, '1', (New-Object System.Text.UTF8Encoding $false))
        $win = $script:shellWin
        $t = $win.FindName('TxtSyncStatus')
        if ($t) { $t.Text = '正在停止，等当前实例结束…'; $t.Foreground = Brush '#FF9F0A' }
        Write-Diag '配置同步: 用户请求停止'
    } catch { }
}
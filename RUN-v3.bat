<# :
@echo off
:: ----------------------------------------------------------------------------------
:: [1. 배치파일 래퍼 (Batch Wrapper)]
:: ----------------------------------------------------------------------------------
chcp 65001 > nul
title Winget Auto Manager (MARM Ultimate Final)
echo.
echo  [System] MARM Protocol: Loading PowerShell Environment...
echo.

:: PowerShell 실행
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"


:: ▼▼▼ [종료 대기] 로그 확인용 ▼▼▼
echo.
echo  =======================================================
echo  [System] 모든 스크립트 실행이 종료되었습니다.
echo  로그를 확인한 후, 창을 닫으려면 아무 키나 누르세요...
echo  =======================================================
pause
goto :eof
#>

# ----------------------------------------------------------------------------------
# [2. PowerShell 로직 (Main Logic)]
# ----------------------------------------------------------------------------------

# [설정 0] 콘솔 인코딩 강제 설정 (한글 깨짐 방지)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# [설정 1] 작업할 최상위 루트 폴더 경로 (★본인 경로에 맞게 수정 필수★)
$BaseDir = "C:\Users\wnsgu\Documents\.wingetmanifests"

# ---------------------------------------------------------
# [함수 정의] 로그 및 유틸리티
# ---------------------------------------------------------
function Print-Msg ($msg, $color="Cyan") {
    $TimeParams = @{ Format = 'HH:mm:ss' }
    Write-Host "[$((Get-Date).ToString($TimeParams.Format))] $msg" -ForegroundColor $color
}

function Confirm-Continue {
    Write-Host -NoNewline ">> 계속 진행하려면 [Enter]를 누르세요 (중단: n) : "
    $input = Read-Host
    if ($input -eq 'n') {
        Print-Msg "[User Abort] 사용자에 의해 작업이 취소되었습니다." "Red"
        Start-Sleep -Seconds 1
        exit
    }
}

# ---------------------------------------------------------
# [Step 0] 사전 의존성 및 로그인 검사 (GitHub CLI)
# ---------------------------------------------------------
Clear-Host
Print-Msg "=== Winget 저장소 관리 도구 (Ver. MARM Ultimate Final) ===" "Green"

# 0-1. 설치 확인
if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Missing Dependency] GitHub CLI (gh)가 없습니다." "Red"
    Write-Host "------------------------------------------------" 
    
    Write-Host -NoNewline ">> 설치하시겠습니까? [Y/n] : "
    $install = Read-Host
    if ($install -eq 'n') { exit }
    
    winget install GitHub.cli
    Print-Msg "설치 완료. 스크립트를 재실행해주세요." "Green"
    Pause
    exit
}

# 0-2. 로그인 확인 (MARM 추가 보완)
Print-Msg "GitHub 로그인 상태를 점검합니다..." "Gray"
try {
    gh auth status *>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Not Logged In" }
    Print-Msg "[System] GitHub 로그인 확인됨." "Green"
} catch {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Auth Warning] GitHub에 로그인되어 있지 않습니다." "Red"
    Print-Msg "Release 업로드를 위해 로그인이 필요합니다." "Yellow"
    Write-Host "------------------------------------------------"
    
    Write-Host -NoNewline ">> 지금 로그인하시겠습니까? (브라우저 연동) [Y/n] : "
    $login = Read-Host
    if ($login -eq 'n') {
        Print-Msg "로그인을 거부하여 스크립트를 종료합니다." "Red"
        exit
    }
    
    gh auth login -p https -w
    Print-Msg "로그인 절차가 완료되었습니다." "Green"
}

# ---------------------------------------------------------
# [Step 1] 초기화 및 동기화
# ---------------------------------------------------------
Print-Msg "기준 경로: $BaseDir" "Gray"

# 1-1. 루트 이동
if (-not (Test-Path $BaseDir)) {
    Print-Msg "[Critical Error] 기준 경로를 찾을 수 없습니다." "Red"
    Pause
    exit
}
Set-Location -Path $BaseDir

# 1-2. 브랜치 감지
try {
    $CurrentBranch = git branch --show-current
    if ([string]::IsNullOrWhiteSpace($CurrentBranch)) { throw "브랜치 정보 없음" }
    Print-Msg "현재 작업 브랜치: [$CurrentBranch]" "Cyan"
} catch {
    Print-Msg "[Git Error] 저장소 초기화 문제 발생." "Red"
    Pause
    exit
}

# 1-3. 원격 동기화 (Auto-Rescue)
Print-Msg "원격 저장소 동기화 중 (git pull)..." "Yellow"
git pull origin $CurrentBranch

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Critical Error] git pull 충돌 발생!" "Red"
    Print-Msg "자동 복구(Rollback)를 시도합니다." "Yellow"
    
    git merge --abort 2>$null
    
    Print-Msg "[Auto-Rescue] 파일이 안전하게 복구되었습니다." "Green"
    Pause
    exit
}
Print-Msg "동기화 완료." "Green"

# ---------------------------------------------------------
# [Step 2] 폴더 선택
# ---------------------------------------------------------
Write-Host "`n작업할 앱의 폴더 이름은 무엇입니까? (예: VkDiag\latest)"
Print-Msg "Tip: 빈 엔터 입력 시 -> Winget/Release 스킵 -> Git 동기화만 수행" "Gray"
$TargetFolder = Read-Host "폴더 이름 입력"

$SkipWinget = $false

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    Write-Host "`n------------------------------------------------"
    Print-Msg "[Skip] 폴더 미입력. Git 동기화 모드로 직행합니다." "Green"
    Write-Host "------------------------------------------------`n"
    $SkipWinget = $true
} else {
    $FullPath = Join-Path -Path $BaseDir -ChildPath $TargetFolder

    if (-not (Test-Path $FullPath)) {
        Print-Msg "새 폴더를 생성합니다: $FullPath" "Yellow"
        New-Item -ItemType Directory -Path $FullPath | Out-Null
        $IsNewFolder = $true
    } else {
        Print-Msg "기존 폴더 진입: $FullPath" "Cyan"
        $IsNewFolder = $false
    }

    Set-Location -Path $FullPath
    Write-Host "`n------------------------------------------------"
    Print-Msg "작업 디렉토리 이동 완료." "Green"
    Write-Host "------------------------------------------------`n"
}

# ---------------------------------------------------------
# [Step 3] Release 자동화 & WingetCreate
# ---------------------------------------------------------
if (-not $SkipWinget) {
    
    # [3-1] 파일 감지 및 업로드
    $Binaries = Get-ChildItem -Path . -Include *.zip,*.exe,*.msi -File
    
    if ($Binaries.Count -gt 0) {
        $BinFile = $Binaries[0]
        Write-Host "------------------------------------------------" -ForegroundColor Yellow
        Print-Msg "감지됨: 업로드 가능한 파일 [$($BinFile.Name)]" "Yellow"
        Write-Host -NoNewline ">> GitHub Release에 업로드하시겠습니까? [Y/n] : "
        $doUpload = Read-Host

        if ($doUpload -ne 'n') {
            $ReleaseTag = Read-Host ">> 릴리즈 태그(버전) 입력 (예: 1.0.0) "
            if ([string]::IsNullOrWhiteSpace($ReleaseTag)) { $ReleaseTag = "v$((Get-Date).ToString('yyyyMMdd'))" }

            Print-Msg "GitHub Release 업로드 중... (gh release create)" "Cyan"
            try {
                gh release create $ReleaseTag $BinFile.Name --title "$ReleaseTag" --notes "Uploaded via MARM Auto Manager"
                
                if ($LASTEXITCODE -eq 0) {
                    # URL 추출
                    $RepoUrl = git remote get-url origin
                    $RepoUrl = $RepoUrl -replace '\.git$', ''
                    $DownloadUrl = "$RepoUrl/releases/download/$ReleaseTag/$($BinFile.Name)"
                    
                    Print-Msg "업로드 성공!" "Green"
                    Print-Msg "URL: $DownloadUrl" "Green"
                    
                    Set-Clipboard -Value $DownloadUrl
                    Print-Msg ">> [OK] URL이 클립보드에 복사되었습니다! (Ctrl+V 사용)" "Yellow"

                    Write-Host -NoNewline "`n>> 로컬 파일($($BinFile.Name))을 삭제하시겠습니까? [Y/n] : "
                    $delFile = Read-Host
                    if ($delFile -ne 'n') {
                        Remove-Item $BinFile.FullName
                        Print-Msg "로컬 파일 삭제 완료." "Gray"
                    }
                } else {
                    Print-Msg "업로드 실패. (로그를 확인하세요)" "Red"
                }
            } catch {
                Print-Msg "GitHub CLI 실행 중 오류 발생: $_" "Red"
            }
        }
    }

    # [3-2] WingetCreate
    Write-Host "------------------------------------------------`n"
    $HasYaml = (Get-ChildItem -Path . -Filter "*.yaml").Count -gt 0

    if ($HasYaml -and -not $IsNewFolder) {
        Print-Msg "[Smart Mode] 기존 YAML 감지 -> 'update' 모드" "Green"
        $WingetCmd = "update"
    } else {
        Print-Msg "[Smart Mode] 파일 없음/새 폴더 -> 'new' 모드" "Green"
        $WingetCmd = "new"
    }

    Print-Msg "실행: wingetcreate $WingetCmd" "Cyan"
    if ($Binaries.Count -gt 0 -and $doUpload -ne 'n') {
        Print-Msg "팁: 'InstallerUrl' 입력 시 Ctrl+V를 누르세요." "Yellow"
    }

    try {
        Invoke-Expression "wingetcreate $WingetCmd"
    } catch {
        Print-Msg "[Error] wingetcreate 실패. 상세: $_" "Red"
        Pause
        exit
    }

    Write-Host "`n"
    Print-Msg "Manifest 완료. Git 작업을 준비합니다." "Green"
    Confirm-Continue
}

# ---------------------------------------------------------
# [Step 4] Git 업로드 (커밋 & 푸시)
# ---------------------------------------------------------
Set-Location -Path $BaseDir
Print-Msg "저장소 루트로 복귀." "Green"

Print-Msg ">>> 변경 상태 (git status)" "Cyan"
git status

Write-Host "`n"
Print-Msg "커밋하시겠습니까?" "Yellow"
Confirm-Continue

Print-Msg "스테이징 (git add)..." "Gray"
git add .

$gitStatus = git status --porcelain
if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Skip] 커밋할 변경 사항이 없습니다." "Red"
    Print-Msg "종료합니다." "Gray"
    Write-Host "------------------------------------------------`n"
    exit
}

# 메모장 커밋 & 롤백
Print-Msg "메모장을 엽니다. [저장] 후 [닫기] 하세요." "Yellow"
$env:GIT_EDITOR = "notepad"

try {
    git commit
    if ($LASTEXITCODE -ne 0) { throw "Commit Aborted" }
} catch {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Warning] 커밋 중단됨." "Red"
    Print-Msg ">> 롤백: 스테이징 취소 (git reset)." "Yellow"
    git reset
    Print-Msg "롤백 완료." "Green"
    Write-Host "------------------------------------------------`n"
    exit
}

# 푸시
Print-Msg "GitHub 푸시 중 (git push origin $CurrentBranch)..." "Gray"
git push origin $CurrentBranch

if ($?) {
    Write-Host "`n============================================" -ForegroundColor Green
    Print-Msg "  [SUCCESS] 모든 작업 성공!  " "Green"
    Write-Host "============================================" -ForegroundColor Green
} else {
    Write-Host "`n============================================" -ForegroundColor Red
    Print-Msg "  [FAILURE] Push 실패.  " "Red"
    Write-Host "============================================" -ForegroundColor Red
}
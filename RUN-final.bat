<# :
@echo off
:: ----------------------------------------------------------------------------------
:: [1. 배치파일 래퍼 (Batch Wrapper)]
:: ----------------------------------------------------------------------------------
chcp 65001 > nul
title Winget Auto Manager (MARM Ultimate Final v2)
echo.
echo  [System] MARM Protocol: Loading PowerShell Environment...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"

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
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$BaseDir = "C:\Users\wnsgu\Documents\.wingetmanifests"

function Print-Msg ($msg, $color="Cyan") {
    $TimeParams = @{ Format = 'HH:mm:ss' }
    Write-Host "[$((Get-Date).ToString($TimeParams.Format))] $msg" -ForegroundColor $color
}
function Confirm-Continue {
    Write-Host -NoNewline ">> 계속 진행하려면 [Enter]를 누르세요 (중단: n) : "
    $input = Read-Host
    if ($input -eq 'n') { exit }
}

# [Step 0] 의존성/로그인 검사
Clear-Host
Print-Msg "=== Winget 저장소 관리 도구 (Ver. MARM Final v2) ===" "Green"

if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Print-Msg "[Error] GitHub CLI (gh) 미설치." "Red"
    Pause; exit
}

Print-Msg "GitHub 로그인 상태 점검..." "Gray"
try {
    gh auth status *>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Not Logged In" }
    Print-Msg "[System] GitHub 로그인 확인됨." "Green"
} catch {
    Print-Msg "[Warning] 로그인 필요. 브라우저로 로그인합니다." "Yellow"
    gh auth login -p https -w
}

# [Step 1] 동기화
Print-Msg "기준 경로: $BaseDir" "Gray"
if (-not (Test-Path $BaseDir)) { Print-Msg "경로 없음" "Red"; Pause; exit }
Set-Location -Path $BaseDir

try {
    $CurrentBranch = git branch --show-current
    Print-Msg "현재 브랜치: [$CurrentBranch]" "Cyan"
} catch { Print-Msg "Git 초기화 오류" "Red"; exit }

Print-Msg "원격 동기화 (git pull)..." "Yellow"
git pull origin $CurrentBranch
if ($LASTEXITCODE -ne 0) {
    Print-Msg "[Critical] 충돌 발생! 자동 복구 실행." "Red"
    git merge --abort 2>$null
    Print-Msg "[Auto-Rescue] 복구 완료. 다시 실행하세요." "Green"
    Pause; exit
}
Print-Msg "동기화 완료." "Green"

# [Step 2] 폴더 선택
Write-Host "`n작업할 앱의 폴더 이름은 무엇입니까? (예: VkDiag\latest)"
Print-Msg "Tip: 빈 엔터 -> Winget 건너뛰고 Git 동기화만 수행" "Gray"
$TargetFolder = Read-Host "폴더 이름 입력"
$SkipWinget = $false

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    Print-Msg "[Skip] Git 동기화 모드로 직행." "Green"
    $SkipWinget = $true
} else {
    $FullPath = Join-Path -Path $BaseDir -ChildPath $TargetFolder
    if (-not (Test-Path $FullPath)) {
        New-Item -ItemType Directory -Path $FullPath | Out-Null
        Print-Msg "새 폴더 생성: $FullPath" "Yellow"
        $IsNewFolder = $true
    } else {
        Print-Msg "폴더 진입: $FullPath" "Cyan"
        $IsNewFolder = $false
    }
    Set-Location -Path $FullPath
}

# [Step 3] Release & Winget
if (-not $SkipWinget) {
    # 3-1. 파일 감지
    $Binaries = Get-ChildItem -Path .\* -Include *.zip,*.exe,*.msi -File
    
    if ($Binaries.Count -gt 0) {
        $BinFile = $Binaries[0]
        Print-Msg "감지됨: [$($BinFile.Name)]" "Yellow"
        Write-Host -NoNewline ">> GitHub Release에 업로드하시겠습니까? [Y/n] : "
        $doUpload = Read-Host
        
        if ($doUpload -ne 'n') {
            $ReleaseTag = Read-Host ">> 태그(버전) 입력 (예: 1.0.0) "
            if ([string]::IsNullOrWhiteSpace($ReleaseTag)) { $ReleaseTag = "v$((Get-Date).ToString('yyyyMMdd'))" }
            
            Print-Msg "업로드 중..." "Cyan"
            try {
                gh release create $ReleaseTag $BinFile.Name --title "$ReleaseTag" --notes "Uploaded via MARM"
                if ($LASTEXITCODE -eq 0) {
                    $RepoUrl = (git remote get-url origin) -replace '\.git$', ''
                    $DownloadUrl = "$RepoUrl/releases/download/$ReleaseTag/$($BinFile.Name)"
                    Print-Msg "성공! URL: $DownloadUrl" "Green"
                    Set-Clipboard -Value $DownloadUrl
                    Print-Msg ">> [OK] URL 클립보드 복사됨 (Ctrl+V)" "Yellow"
                    
                    Write-Host -NoNewline ">> 로컬 파일 삭제? [Y/n] : "
                    if ((Read-Host) -ne 'n') { Remove-Item $BinFile.FullName }
                } else { Print-Msg "업로드 실패." "Red" }
            } catch { Print-Msg "gh 오류: $_" "Red" }
        }
    } else {
        # 파일이 없을 경우 경고
        Print-Msg "[Info] 이 폴더에 업로드할 파일(.zip/.exe)이 없습니다." "Gray"
        Print-Msg "       GitHub Release 업로드 단계를 건너뜁니다." "Gray"
    }

    # 3-2. WingetCreate (무조건 New 모드)
    Write-Host "`n------------------------------------------------"
    Print-Msg "[Winget] 매니페스트 생성을 시작합니다." "Cyan"
    Print-Msg "주의: 'update'는 로컬 파일에서 작동하지 않으므로 항상 'new'로 진행합니다." "Gray"
    Print-Msg "      기존 정보가 있어도 덮어쓰기(Overwrite) 됩니다." "Gray"
    
    if ($Binaries.Count -gt 0 -and $doUpload -ne 'n') {
        Print-Msg "팁: URL 입력 시 Ctrl+V 하세요." "Yellow"
    }
    
    # 무조건 new 실행
	# [수정] 현재 폴더에 결과물 생성 (--out .)
    try { Invoke-Expression "wingetcreate $WingetCmd --out ." } 
    catch { Print-Msg "오류: $_" "Red"; Pause; exit }
    
    Print-Msg "Manifest 완료." "Green"
    Confirm-Continue
}

# [Step 4] Git 업로드
Set-Location -Path $BaseDir
Print-Msg "루트 복귀 & Git Status 확인" "Green"
git status
Write-Host "`n"
Print-Msg "커밋하시겠습니까?" "Yellow"
Confirm-Continue

git add .
if ([string]::IsNullOrWhiteSpace((git status --porcelain))) {
    Print-Msg "[Skip] 변경사항 없음. 종료." "Red"
    exit
}

$env:GIT_EDITOR = "notepad"
try {
    git commit
    if ($LASTEXITCODE -ne 0) { throw }
} catch {
    Print-Msg "[Warning] 커밋 중단. 롤백(reset) 실행." "Red"
    git reset; exit
}

Print-Msg "Push 중..." "Gray"
git push origin $CurrentBranch

if ($?) { Print-Msg "[SUCCESS] 완료!" "Green" } 
else { Print-Msg "[FAILURE] Push 실패" "Red" }
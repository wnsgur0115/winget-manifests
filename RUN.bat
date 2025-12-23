<# :
@echo off
:: ----------------------------------------------------------------------------------
:: [1. 배치파일 래퍼 (Batch Wrapper)]
:: ----------------------------------------------------------------------------------
:: CMD 창의 코드페이지를 UTF-8로 강제 변경 (한글 깨짐 1차 방어)
chcp 65001 > nul
title Winget Auto Manager (MARM Ultimate Final)
echo.
echo  [System] MARM Protocol: Loading PowerShell Environment...
echo.

:: PowerShell 실행 (현재 파일 내용을 읽어서 실행)
:: -NoProfile: 빠른 실행
:: -ExecutionPolicy Bypass: 권한 제한 해제
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"


:: ▼▼▼ [종료 대기] 로그 확인을 위해 창을 유지합니다 ▼▼▼
echo.
echo  =======================================================
echo  [System] 모든 스크립트 실행이 종료되었습니다.
echo  로그를 확인한 후, 창을 닫으려면 아무 키나 누르세요...
echo  =======================================================
pause
:: ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

goto :eof
#>

# ----------------------------------------------------------------------------------
# [2. PowerShell 로직 (Main Logic)]
# ----------------------------------------------------------------------------------

# [설정 0] 한글 출력을 위한 이중 안전장치 (콘솔 인코딩 강제 설정)
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
# [Step 1] 초기화 및 브랜치/폴더 동기화
# ---------------------------------------------------------
Clear-Host
Print-Msg "=== Winget 저장소 관리 도구 (Ver. MARM Ultimate Final) ===" "Green"
Print-Msg "기준 경로: $BaseDir" "Gray"

# 1-1. 루트 폴더 이동
if (-not (Test-Path $BaseDir)) {
    Print-Msg "[Critical Error] 기준 경로($BaseDir)를 찾을 수 없습니다." "Red"
    Pause
    exit
}
Set-Location -Path $BaseDir

# 1-2. 현재 브랜치 자동 감지
try {
    $CurrentBranch = git branch --show-current
    if ([string]::IsNullOrWhiteSpace($CurrentBranch)) { throw "브랜치 정보 없음" }
    Print-Msg "현재 작업 브랜치 감지됨: [$CurrentBranch]" "Cyan"
} catch {
    Print-Msg "[Git Error] Git 저장소가 아니거나 초기화되지 않았습니다." "Red"
    Print-Msg "상세 에러: $_" "Red"
    Pause
    exit
}

# 1-3. 원격 저장소 동기화 (Auto-Rescue 적용)
Print-Msg "원격 저장소와 동기화를 시도합니다 (git pull)..." "Yellow"
git pull origin $CurrentBranch

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Critical Error] git pull 중 오류(충돌)가 발생했습니다!" "Red"
    Print-Msg "파일이 꼬이는 것을 방지하기 위해 자동 복구를 시도합니다." "Yellow"
    
    # [MARM 안전장치 1] 충돌 발생 시 즉시 롤백 (git merge --abort)
    git merge --abort 2>$null
    
    Print-Msg "[Auto-Rescue] 'git merge --abort' 실행 완료." "Green"
    Print-Msg "로컬 파일이 충돌 전 상태로 안전하게 복구되었습니다." "Green"
    Print-Msg "원격 저장소와 로컬 상태를 수동으로 확인한 후 다시 실행하세요." "Gray"
    Write-Host "------------------------------------------------`n"
    Pause
    exit
}
Print-Msg "동기화 완료. 최신 상태입니다." "Green"

# ---------------------------------------------------------
# [Step 2] 폴더 선택 및 모드 결정 (직관적 스킵 적용)
# ---------------------------------------------------------
Write-Host "`n작업할 앱의 폴더 이름은 무엇입니까? (예: VkDiag)"
Print-Msg "Tip: 입력 없이 [Enter]를 누르면 Winget 작업을 건너뛰고 Git 동기화만 수행합니다." "Gray"
$TargetFolder = Read-Host "폴더 이름 입력"

$SkipWinget = $false

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    # [사용자 요청 반영] 빈 엔터 시 Winget 스킵 -> Git 모드 직행
    Write-Host "`n------------------------------------------------"
    Print-Msg "[Skip] 폴더 이름이 입력되지 않았습니다." "Yellow"
    Print-Msg "Winget 패키지 생성 단계를 건너뛰고, Git 동기화 모드로 진입합니다." "Green"
    Write-Host "------------------------------------------------`n"
    $SkipWinget = $true
} else {
    # 폴더가 입력된 경우 정상 진행
    $FullPath = Join-Path -Path $BaseDir -ChildPath $TargetFolder

    # 폴더 생성 로직
    if (-not (Test-Path $FullPath)) {
        Print-Msg "폴더가 없어 새로 생성합니다: $FullPath" "Yellow"
        New-Item -ItemType Directory -Path $FullPath | Out-Null
        $IsNewFolder = $true
    } else {
        Print-Msg "기존 폴더를 찾았습니다: $FullPath" "Cyan"
        $IsNewFolder = $false
    }

    Set-Location -Path $FullPath
    Write-Host "`n------------------------------------------------"
    Print-Msg "작업 디렉토리 이동 완료." "Green"
    Write-Host "------------------------------------------------`n"
}

# ---------------------------------------------------------
# [Step 3] WingetCreate 실행 (Skip 플래그 확인)
# ---------------------------------------------------------
if (-not $SkipWinget) {
    # 스마트 모드 결정 (New vs Update)
    $HasYaml = (Get-ChildItem -Path . -Filter "*.yaml").Count -gt 0

    if ($HasYaml -and -not $IsNewFolder) {
        Print-Msg "[Smart Mode] 기존 YAML 파일이 감지되었습니다." "Green"
        Print-Msg ">> 'update' 모드로 실행합니다. (버전/URL만 입력하면 됨)" "Yellow"
        $WingetCmd = "update"
    } else {
        Print-Msg "[Smart Mode] 파일이 없거나 새 폴더입니다." "Green"
        Print-Msg ">> 'new' 모드로 실행합니다. (모든 정보 입력 필요)" "Yellow"
        $WingetCmd = "new"
    }

    Print-Msg "명령어 실행: wingetcreate $WingetCmd" "Cyan"
    Write-Host "    (팁: 로컬 경로는 file:///C:/... 사용)`n"

    try {
        Invoke-Expression "wingetcreate $WingetCmd"
    } catch {
        Print-Msg "[Exec Error] wingetcreate 실행 중 치명적 오류 발생." "Red"
        Print-Msg "상세 에러: $_" "Red"
        Pause
        exit
    }

    Write-Host "`n"
    Print-Msg "Manifest 작업이 끝났습니다. Git 작업을 준비합니다." "Green"
    Confirm-Continue
}

# ---------------------------------------------------------
# [Step 4] Git 업로드 (검증 및 커밋)
# ---------------------------------------------------------
Set-Location -Path $BaseDir
Print-Msg "Git 처리를 위해 저장소 루트로 복귀했습니다." "Green"

# 변경사항 확인
Print-Msg ">>> 현재 변경된 파일 상태 (git status)" "Cyan"
git status

Write-Host "`n"
Print-Msg "위 변경 사항을 커밋하시겠습니까?" "Yellow"
Confirm-Continue

# 파일 스테이징
Print-Msg "파일 스테이징 (git add)..." "Gray"
git add .

# [안전장치 2] 빈 커밋 방지 (변경사항 없으면 종료)
$gitStatus = git status --porcelain
if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Skip] 커밋할 변경 사항이 없습니다." "Red"
    Print-Msg "스크립트를 종료합니다." "Gray"
    Write-Host "------------------------------------------------`n"
    exit
}

# ----------------------------------------------------------------
# 메모장 커밋 & 롤백 시스템
# ----------------------------------------------------------------
Print-Msg "커밋 메시지 입력을 위해 메모장을 엽니다." "Yellow"
Print-Msg "작성 후 [저장(Ctrl+S)] -> [닫기(Alt+F4)] 하세요." "Cyan"

# 환경변수: Git 에디터를 메모장으로 강제
$env:GIT_EDITOR = "notepad"

try {
    git commit
    if ($LASTEXITCODE -ne 0) { throw "Commit Aborted" }
} catch {
    Write-Host "`n------------------------------------------------" -ForegroundColor Red
    Print-Msg "[Warning] 커밋이 중단되었습니다 (내용 없음 또는 강제 종료)." "Red"
    
    # [안전장치 3] 롤백 로직 (스테이징 취소)
    Print-Msg ">> 롤백 프로세스: 스테이징을 취소합니다 (git reset)." "Yellow"
    git reset
    
    Print-Msg "롤백 완료. 작업 내용은 안전하게 보존되었습니다." "Green"
    Write-Host "------------------------------------------------`n"
    exit
}

# 푸시 진행
Print-Msg "GitHub로 푸시 중 (git push origin $CurrentBranch)..." "Gray"
git push origin $CurrentBranch

if ($?) {
    Write-Host "`n============================================" -ForegroundColor Green
    Print-Msg "  [SUCCESS] 모든 작업이 성공적으로 완료되었습니다!  " "Green"
    Write-Host "============================================" -ForegroundColor Green
} else {
    Write-Host "`n============================================" -ForegroundColor Red
    Print-Msg "  [FAILURE] Git Push 중 오류가 발생했습니다.  " "Red"
    Print-Msg "  네트워크나 권한을 확인해주세요.  " "Red"
    Write-Host "============================================" -ForegroundColor Red
}

# (배치파일 래퍼의 pause로 인해 여기서 창이 바로 닫히지 않음)
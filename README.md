# Terraform CI/CD + Azure OIDC + Codex Plan Review + Drift Detection ハンズオン

このリポジトリは、GitHub Actions と Terraform を使って、Azure 上に検証用 Storage Account を作成・更新するハンズオンです。

主な目的は、Terraform の CI/CD を GitHub Actions で構成し、Azure への認証に Client Secret ではなく OIDC を使う流れを体験することです。

さらに、Codex GitHub Action を使って `terraform plan` の結果を日本語で解説し、Pull Request のタイトル・説明文と Terraform plan の内容が合っているかを確認する仕組みも組み込んでいます。

加えて、1日1回 `terraform plan` を自動実行し、Terraform 管理状態と Azure 上の実リソースに差分がある場合に GitHub Issue を作成・更新する Drift Detection も含めています。

## このハンズオンで学ぶこと

このハンズオンでは、次の内容を扱います。

* Terraform の remote state を Azure Blob Storage に保存する
* GitHub Actions から Azure へ OIDC で認証する
* Pull Request 作成時に `terraform plan` を自動実行する
* Pull Request に Terraform plan の結果をコメントする
* Codex GitHub Action を使って Terraform plan の内容を日本語で解説する
* Pull Request のタイトル・説明文と Terraform plan の内容を比較し、変更意図と差分が合っているかを確認する
* `main` ブランチへの merge 後に Terraform Apply workflow を自動起動する
* GitHub Environment の承認後に `terraform apply` を実行する
* `terraform plan -out=tfplan` で作成した plan ファイルを artifact として apply job に渡す
* 1日1回、Terraform の差分を確認し、差分があれば GitHub Issue を作成・更新する
* Terraform 実行用 Service Principal の権限を Resource Group スコープに絞る
* OpenAI API key を GitHub Secrets で管理する
* Public リポジトリで見せたくないAzure識別子やstate用Storage Account名を GitHub Secrets で管理する

この構成は学習用の最小構成です。本番利用する場合は、権限設計、state保護、レビュー運用、監査、destroy運用、ブランチ保護、外部fork PRへの対応などを追加で検討してください。

## 全体像

このハンズオンでは、Azure 側に次のリソースを事前に用意します。

* Terraform state 保存用 Resource Group
* Terraform state 保存用 Storage Account
* Terraform state 保存用 Blob Container
* Terraform 実行対象 Resource Group
* GitHub Actions 用 App Registration / Service Principal
* GitHub Actions OIDC 用 Federated Credential
* Azure RBAC

そのうえで、Terraform により検証用 Storage Account を 1 つ作成します。

```text
GitHub Pull Request
  ↓
Terraform CI
  ↓
terraform fmt / validate / plan
  ↓
plan.txt を artifact として保存
  ↓
Codex GitHub Action が plan.txt と PRタイトル・本文を読み取る
  ↓
Codex が Terraform plan を日本語で解説
  ↓
Codex が PRの意図と plan の整合性を確認
  ↓
PRに Codex解説つき plan コメントを投稿
  ↓
merge
  ↓
Terraform Apply workflow が自動起動
  ↓
plan jobで tfplan を作成
  ↓
GitHub Environment 承認待ち
  ↓
approve
  ↓
apply jobで tfplan を適用
  ↓
AzureにStorage Account作成・更新
```

Drift Detection は、通常のPull Requestとは別に、定期実行されます。

```text
1日1回のスケジュール実行
  ↓
Terraform Drift Detection workflow
  ↓
terraform plan -detailed-exitcode
  ↓
差分なし
  ↓
何もしない、または既存Issueを閉じる

差分あり
  ↓
GitHub Issueを作成または更新
  ↓
人間がplan内容を確認
```

## 作成されるAzureリソース

Terraform が作成するリソースは、検証用 Storage Account です。

```text
Resource Group:
  rg-tf-handson-sandbox-jpe

Terraformで作成するリソース:
  検証用 Storage Account
```

一方、remote state 用 Storage Account は Terraform 実行前に Azure CLI で作成します。

```text
state用 Resource Group:
  rg-tfstate-handson-jpe

state用 Storage Account:
  sttfstateXXXXXXXX

state用 Container:
  tfstate

state key:
  demo/sandbox/main.tfstate
```

remote state 用 Storage Account と、Terraform で作成する検証用 Storage Account は別物です。

## リポジトリ構成

```text
.
├── .github/
│   ├── workflows/
│   │   ├── terraform-ci.yml
│   │   ├── terraform-apply.yml
│   │   └── terraform-drift-detection.yml
│   │
│   └── codex/
│       └── prompts/
│           └── terraform-plan-explain.md
│
└── infra/
    └── terraform/
        ├── versions.tf
        ├── provider.tf
        ├── backend.hcl
        ├── variables.tf
        ├── main.tf
        ├── outputs.tf
        └── terraform.tfvars
```

## 各ファイルの役割

### `.github/workflows/terraform-ci.yml`

Pull Request 作成時に実行される CI workflow です。

実行内容は次の通りです。

* Azure へ OIDC でログイン
* Terraform をセットアップ
* `terraform init`
* `terraform fmt -check`
* `terraform validate`
* `terraform plan`
* `terraform show -no-color` で plan 結果を `plan.txt` に保存
* `plan.txt` を artifact として保存
* Codex GitHub Action で plan の内容を日本語で解説
* Pull Request のタイトル・説明文と plan の内容が整合しているかを確認
* Pull Request に Codex解説つきの `Terraform Plan Result` コメントを投稿

この workflow では `terraform apply` は実行しません。

PRコメントでは、まずCodexによる解説を表示し、Terraform planの生ログは折りたたみ表示にしています。

### `.github/workflows/terraform-apply.yml`

`main` ブランチへの push、または手動実行で起動する Apply workflow です。

実行内容は次の通りです。

* `plan` jobで `terraform plan -out=tfplan` を実行
* `tfplan` を artifact として保存
* `apply` jobで GitHub Environment 承認を待つ
* 承認後、artifact から `tfplan` を取得
* `terraform apply tfplan` を実行

通常は、Pull Request を merge するとこの workflow が自動起動します。

### `.github/workflows/terraform-drift-detection.yml`

1日1回、または手動実行で Terraform の差分を確認する workflow です。

実行内容は次の通りです。

* Azure へ OIDC でログイン
* Terraform をセットアップ
* `terraform init`
* `terraform plan -detailed-exitcode` を実行
* 差分がなければ何もしない
* 差分があれば GitHub Issue を作成または更新する
* 以前作成したDrift検知Issueがあり、最新チェックで差分がなくなっていればIssueを閉じる

この workflow は、Azure上で手動変更された可能性や、`main` のTerraformコードがまだapplyされていない可能性を検知するためのものです。

ただし、検知できるのは Terraform が管理しているリソースの差分です。Terraform 管理外のリソースをAzure Portalなどで追加・変更しても、この workflow では検知できません。

### `.github/codex/prompts/terraform-plan-explain.md`

Codex に Terraform plan をどのように解説させるかを定義するプロンプトファイルです。

このファイルでは、Codexに次の観点で解説するよう指示しています。

* 変更の概要
* PRの意図との整合性
* 作成されるリソース
* 変更されるリソース
* 削除されるリソース
* 注意すべきリスク
* レビュー時の確認ポイント
* applyしてよさそうかの所感

GitHub Actions の中で、次の情報を結合した `codex-prompt.md` を作成し、Codex に渡します。

```text
Codexへの基本指示
  +
Pull Request のタイトル
  +
Pull Request の説明文
  +
Terraform plan の本文
```

これにより、Codexは単にplanを要約するだけでなく、PRで説明されている変更意図と、実際のTerraform planの内容が合っているかも確認します。

### `infra/terraform/versions.tf`

Terraform 本体と Provider のバージョン条件を定義します。

このハンズオンでは、AzureRM Provider v3 系を使います。

```hcl
azurerm = {
  source  = "hashicorp/azurerm"
  version = "~> 3.116"
}
```

### `infra/terraform/provider.tf`

AzureRM Provider の設定を定義します。

このハンズオンでは、Resource Provider の自動登録を無効化しています。

```hcl
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  skip_provider_registration = true
}
```

これは、GitHub Actions 用 Service Principal に Subscription 全体の Contributor 権限を与えず、必要な Resource Group だけを操作させるためです。

必要な Azure Resource Provider は、管理者または作業者が事前に登録しておきます。

今回必要になる主な Resource Provider は次です。

```text
Microsoft.Storage
```

### `infra/terraform/backend.hcl`

remote state の backend 設定用ファイルです。

このハンズオンでは、backend の具体値はこのファイルには書かず、GitHub Actions の `terraform init` で `-backend-config` として渡します。

### `infra/terraform/main.tf`

Terraform で作成する Azure リソースを定義します。

このハンズオンでは、既存の Resource Group を参照し、その中に検証用 Storage Account を作成します。

### `infra/terraform/variables.tf`

Terraform に渡す変数を定義します。

### `infra/terraform/terraform.tfvars`

学習用の固定値を定義します。

```hcl
customer_name    = "demo"
environment_name = "sandbox"
```

### `infra/terraform/outputs.tf`

Terraform 実行後に表示する値を定義します。

## 事前に必要なもの

このハンズオンには、次が必要です。

* Azure Subscription
* GitHub リポジトリ
* Azure Cloud Shell または Azure CLI
* GitHub リポジトリの管理権限
* Azure で Resource Group、Storage Account、App Registration、Service Principal、RBAC を作成できる権限
* OpenAI API key
* GitHub Actions で Codex GitHub Action を実行するための Repository Secret

初心者の場合、Azure 側の作業は Azure Cloud Shell の Bash で行うのがおすすめです。

## Azure側の初期セットアップ

### 1. 変数を設定する

Azure Cloud Shell の Bash で実行します。

```bash
OWNER="<GitHubのOwner名>"
REPO="<GitHubのリポジトリ名>"

LOCATION="japaneast"

RG_STATE="rg-tfstate-handson-jpe"
RG_TARGET="rg-tf-handson-sandbox-jpe"

SUFFIX=$RANDOM$RANDOM
ST_STATE="sttfstate${SUFFIX:0:8}"
CONTAINER_STATE="tfstate"

STATE_KEY="demo/sandbox/main.tfstate"

APP_NAME="sp-gha-terraform-handson"
GITHUB_ENVIRONMENT="terraform-sandbox"
```

### 2. Subscription を確認する

```bash
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table
```

必要に応じて Subscription を切り替えます。

```bash
az account set --subscription "<Azure Subscription ID>"
```

以降で使う値を取得します。

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo $SUBSCRIPTION_ID
echo $TENANT_ID
```

### 3. remote state 用 Resource Group を作成する

```bash
az group create \
  --name $RG_STATE \
  --location $LOCATION
```

### 4. remote state 用 Storage Account を作成する

```bash
az storage account create \
  --name $ST_STATE \
  --resource-group $RG_STATE \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2
```

Blob versioning と削除保護を有効化します。

```bash
az storage account blob-service-properties update \
  --account-name $ST_STATE \
  --resource-group $RG_STATE \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 7 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 7
```

### 5. remote state 用 Container を作成する

```bash
az storage container create \
  --name $CONTAINER_STATE \
  --account-name $ST_STATE \
  --auth-mode login
```

### 6. Terraform 実行対象 Resource Group を作成する

```bash
az group create \
  --name $RG_TARGET \
  --location $LOCATION
```

### 7. App Registration / Service Principal を作成する

```bash
APP_ID=$(az ad app create \
  --display-name $APP_NAME \
  --query appId \
  -o tsv)

echo $APP_ID
```

```bash
az ad sp create --id $APP_ID
```

```bash
SP_OBJECT_ID=$(az ad sp show \
  --id $APP_ID \
  --query id \
  -o tsv)

echo $SP_OBJECT_ID
```

### 8. Service Principal に Azure RBAC を付与する

Terraform 対象 Resource Group に Contributor を付与します。

```bash
TARGET_SCOPE=$(az group show \
  --name $RG_TARGET \
  --query id \
  -o tsv)

az role assignment create \
  --assignee-object-id $SP_OBJECT_ID \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope $TARGET_SCOPE
```

state 用 Storage Account に Storage Blob Data Contributor を付与します。

```bash
STATE_STORAGE_SCOPE=$(az storage account show \
  --name $ST_STATE \
  --resource-group $RG_STATE \
  --query id \
  -o tsv)

az role assignment create \
  --assignee-object-id $SP_OBJECT_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope $STATE_STORAGE_SCOPE
```

### 9. Resource Provider を確認する

このハンズオンでは、AzureRM Provider の Resource Provider 自動登録を無効化しています。

そのため、`Microsoft.Storage` が登録済みであることを確認します。

```bash
az provider show \
  --namespace Microsoft.Storage \
  --query "registrationState" \
  -o tsv
```

`Registered` であれば OK です。

未登録の場合は、必要な権限を持つユーザーで次を実行します。

```bash
az provider register --namespace Microsoft.Storage
```

### 10. Federated Identity Credential を作成する

GitHub Actions から OIDC で Azure にログインできるように、App Registration に信頼条件を追加します。

PR plan 用です。

```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters "{
    \"name\": \"github-pr-plan\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${OWNER}/${REPO}:pull_request\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
```

main ブランチ用です。

```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${OWNER}/${REPO}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
```

GitHub Environment apply 用です。

```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters "{
    \"name\": \"github-env-terraform-sandbox\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${OWNER}/${REPO}:environment:${GITHUB_ENVIRONMENT}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
```

作成結果を確認します。

```bash
az ad app federated-credential list \
  --id $APP_ID \
  --query "[].{name:name, subject:subject}" \
  -o table
```

## GitHub側の設定

### Repository Secrets

GitHub リポジトリで以下を開きます。

```text
Settings
  → Secrets and variables
  → Actions
  → Secrets
```

次の Repository secrets を追加します。

| Name                       | Value                     |
| -------------------------- | ------------------------- |
| `OPENAI_API_KEY`           | OpenAI API key            |
| `AZURE_CLIENT_ID`          | App Registration の App ID |
| `AZURE_TENANT_ID`          | Azure Tenant ID           |
| `AZURE_SUBSCRIPTION_ID`    | Azure Subscription ID     |
| `TF_STATE_STORAGE_ACCOUNT` | state 用 Storage Account 名 |

`OPENAI_API_KEY` は Codex GitHub Action から OpenAI API を呼び出すために使います。

`AZURE_CLIENT_ID`、`AZURE_TENANT_ID`、`AZURE_SUBSCRIPTION_ID` は、それ単体でAzureにログインできる秘密情報ではありませんが、Azure環境に固有の識別子です。このリポジトリはPublicであるため、見せたくない情報として Secrets に格納しています。

`TF_STATE_STORAGE_ACCOUNT` は Azure 全体で一意なStorage Account名であり、state保存先を推測できる情報でもあるため Secrets に格納しています。

### Repository Variables

GitHub リポジトリで以下を開きます。

```text
Settings
  → Secrets and variables
  → Actions
  → Variables
```

次の Repository variables を追加します。

| Name                       | Value                       |
| -------------------------- | --------------------------- |
| `TF_STATE_RESOURCE_GROUP`  | `rg-tfstate-handson-jpe`    |
| `TF_STATE_CONTAINER`       | `tfstate`                   |
| `TF_STATE_KEY`             | `demo/sandbox/main.tfstate` |
| `TF_TARGET_RESOURCE_GROUP` | `rg-tf-handson-sandbox-jpe` |
| `LOCATION`                 | `japaneast`                 |

このハンズオンでは Client Secret は使いません。

Azureへの認証は、GitHub Actions OIDC と Microsoft Entra ID の Federated Identity Credential を使います。

### GitHub Environment

GitHub リポジトリで以下を開きます。

```text
Settings
  → Environments
  → New environment
```

Environment 名は次にします。

```text
terraform-sandbox
```

可能であれば Required reviewers を設定します。

```text
Required reviewers:
  自分
```

これにより、`terraform apply` の直前で人間の承認を挟めます。

### Actions の権限設定

PRコメントやIssue作成を行うため、GitHub Actions に書き込み権限が必要です。

GitHub リポジトリで以下を開きます。

```text
Settings
  → Actions
  → General
  → Workflow permissions
```

次を選択します。

```text
Read and write permissions
```

## 実行方法

### 1. feature ブランチを作成する

```bash
git checkout main
git pull origin main
git checkout -b feature/terraform-change
```

### 2. Terraform ファイルを変更する

例として、`infra/terraform/main.tf` のタグを変更します。

```hcl
common_tags = {
  customer    = var.customer_name
  environment = var.environment_name
  managed_by  = "terraform"
  purpose     = "handson"
  test        = "auto-apply"
}
```

### 3. commit して push する

```bash
git add infra/terraform/main.tf
git commit -m "Update Terraform tags"
git push -u origin feature/terraform-change
```

### 4. Pull Request を作成する

GitHub で Pull Request を作成します。

```text
base: main
compare: feature/terraform-change
```

PRのタイトルと説明文には、何を変更したいのかを書きます。

例:

```text
Title:
  Add test tag to Storage Account

Description:
  Storage Accountに検証用タグ test = auto-apply を追加します。
  リソースの作成・削除は意図していません。
```

Codexは、このPRタイトル・説明文とTerraform planの内容を比較し、変更意図とplan内容が合っているかを確認します。

### 5. Terraform CI を確認する

Pull Request 作成後、`Terraform CI` workflow が実行されます。

確認ポイントは次の通りです。

* `terraform init` が成功する
* `terraform fmt -check` が成功する
* `terraform validate` が成功する
* `terraform plan` が成功する
* `plan.txt` が artifact として保存される
* Codex GitHub Action が成功する
* Pull Request に `Terraform Plan Result` コメントが投稿される

PRコメントには、次の内容が含まれます。

* CodexによるTerraform planの日本語解説
* PRの意図との整合性評価
* 作成・変更・削除されるリソースの整理
* 注意すべきリスク
* レビュー時の確認ポイント
* Raw Terraform Plan

Codexは、Pull Request のタイトル・説明文と Terraform plan の内容を比較し、PRで説明された意図とplanの内容が合っているかを確認します。

たとえば、PR本文で「Storage Accountにタグを追加する」と説明している場合、planにも既存Storage Accountのタグ変更だけが出ていれば、意図とplanが概ね一致していると判断できます。

一方で、PR本文では小さなタグ変更に見えるのに、planに削除や再作成が含まれる場合は、Codexが注意喚起します。

### 6. Pull Request を merge する

Plan の内容とCodexの解説に問題がなければ、Pull Request を merge します。

### 7. Terraform Apply workflow の自動起動を確認する

`main` ブランチへ merge されると、`Terraform Apply` workflow が自動起動します。

```text
Actions
  → Terraform Apply
```

`plan` job が実行され、その後 `apply` job が `terraform-sandbox` Environment の承認待ちになります。

### 8. Environment 承認を行う

GitHub Actions の画面で次を選択します。

```text
Review deployments
  → terraform-sandbox
  → Approve and deploy
```

承認後、`terraform apply tfplan` が実行されます。

## Drift Detection の実行方法

### 定期実行

`Terraform Drift Detection` workflow は、1日1回スケジュール実行されます。

```text
毎日 22:00 UTC
日本時間ではおおよそ 07:00
```

実行対象は default branch、通常は `main` です。

### 手動実行

GitHub Actions 画面から手動実行できます。

```text
Actions
  → Terraform Drift Detection
  → Run workflow
```

### 差分がない場合

Terraform plan の終了コードが `0` になります。

```text
No changes detected.
```

この場合、新しいIssueは作成されません。

既にDrift検知Issueが開いている場合は、最新チェックで差分がなくなったことをコメントし、Issueを閉じます。

### 差分がある場合

Terraform plan の終了コードが `2` になります。

この場合、GitHub Issue が作成または更新されます。

Issueタイトルは次です。

```text
Terraform drift detected for demo/sandbox
```

Issue本文には、次の内容が含まれます。

* workflow名
* 実行ID
* チェック日時
* Working directory
* State key
* Target Resource Group
* Terraform planの内容
* 推奨対応

### Drift Detection のテスト方法

検証用Storage Accountに、Azure PortalまたはAzure CLIで手動タグを追加すると、差分を発生させられます。

まず、Terraform管理対象のStorage Account名を確認します。

```bash
az storage account list \
  --resource-group rg-tf-handson-sandbox-jpe \
  --query "[].name" \
  -o tsv
```

表示された `stdemosandbox...` のStorage Accountに手動タグを追加します。

```bash
az storage account update \
  --name "<検証用Storage Account名>" \
  --resource-group rg-tf-handson-sandbox-jpe \
  --set tags.manual_change=drift-test
```

その後、GitHub Actionsで `Terraform Drift Detection` を手動実行します。

```text
Actions
  → Terraform Drift Detection
  → Run workflow
```

差分が検出されると、Issueが作成または更新されます。

## 作成結果の確認

Azure Cloud Shell で、検証用 Storage Account が作成されていることを確認します。

```bash
az storage account list \
  --resource-group rg-tf-handson-sandbox-jpe \
  --query "[].{name:name, location:location, tags:tags}" \
  -o table
```

remote state が Blob に保存されていることを確認します。

```bash
az storage blob list \
  --account-name "<state用Storage Account名>" \
  --container-name tfstate \
  --auth-mode login \
  --query "[].{name:name}" \
  -o table
```

次が表示されれば OK です。

```text
demo/sandbox/main.tfstate
```

## 再実行して No changes を確認する

もう一度 `Terraform Apply` workflow を実行すると、変更がなければ次のような結果になります。

```text
No changes.
```

または、

```text
0 to add, 0 to change, 0 to destroy
```

これは、Terraform のコード、remote state、Azure 上の実リソースが一致していることを意味します。

## 重要な設計ポイント

### OIDC を使う理由

このハンズオンでは、GitHub Actions から Azure へ Client Secret ではなく OIDC で認証します。

OIDC を使うことで、GitHub Secrets に長期間有効な Client Secret を保存せずに済みます。

### Service Principal の権限

このハンズオンでは、GitHub Actions 用 Service Principal に Subscription 全体の Contributor は付与していません。

代わりに、次のように権限を絞っています。

```text
Terraform対象Resource Group:
  Contributor

state用Storage Account:
  Storage Blob Data Contributor
```

これにより、GitHub Actions が操作できる範囲を限定しています。

### Resource Provider 自動登録を無効化している理由

AzureRM Provider は、既定では Azure Resource Provider を自動登録しようとすることがあります。

しかし、Resource Provider 登録は Subscription 全体に関わる操作です。

このハンズオンでは、Service Principal の権限を広げないため、AzureRM Provider v3 向けに次を設定しています。

```hcl
skip_provider_registration = true
```

必要な Resource Provider は、事前に人間または別の管理プロセスで登録します。

### CodexでTerraform planを解説する理由

Terraform plan の生ログは正確ですが、初心者やTerraformに慣れていないレビュー担当者には読みづらい場合があります。

このハンズオンでは、Codex GitHub Action を使って、Terraform plan の内容を日本語で解説します。

Codexは次の観点でplanを整理します。

```text
何が作られるのか
何が変更されるのか
何が削除されるのか
注意すべきリスクはあるか
PRの説明とplan内容は合っているか
applyしてよさそうか
```

ただし、Codexの解説は最終判断ではありません。

最終的に `terraform apply` してよいかは、人間がPR内容、Terraform plan、Codexの解説を確認して判断します。

### PRの意図との整合性を見る理由

Terraform planは「実際にAzureにどういう変更が入るか」を示します。

一方で、Pull Request のタイトルや説明文は「作成者が何をしたいと思っているか」を示します。

この2つを比較することで、次のような問題に気づきやすくなります。

```text
PRではタグ追加と書かれているのに、planでは削除が出ている
PR本文が空で、変更意図が分からない
PRの説明にない大きな設定変更がplanに含まれている
変更対象のResource Groupが想定と違う
```

このハンズオンでは、CodexにPRタイトル・PR本文・Terraform planをまとめて渡し、意図と差分が合っているかを確認させています。

### Codex jobにAzure権限を持たせない理由

Terraform plan を実行する job には Azure OIDC 認証が必要です。

一方、Codex が行うのは plan の解説だけです。

そのため、workflowでは次のようにjobを分けています。

```text
terraform-plan job
  AzureへOIDCログインする
  terraform planを実行する
  plan.txtをartifact保存する

codex-explain job
  Azureへログインしない
  plan.txt artifactをdownloadする
  Codexで解説する
  PRコメントを投稿する
```

これにより、Codexを実行するjobにはAzure操作権限を持たせずに済みます。

### Drift Detection の考え方

Drift Detection は、Terraform のコード、remote state、Azure 上の実リソースの差分を確認する仕組みです。

このハンズオンでは、`terraform plan -detailed-exitcode` を使って差分の有無を判断します。

```text
0:
  差分なし

1:
  エラー

2:
  差分あり
```

差分がある場合、GitHub Issueを作成または更新します。

ただし、差分があることは必ずしも「Azure Portalで誰かが手動変更した」ことだけを意味しません。

次のようなケースでも差分が出ます。

```text
Azure上で手動変更があった
mainブランチのTerraformコードがまだapplyされていない
Providerの挙動やcomputed valueにより差分が出ている
```

そのため、Issue本文では「ドリフトまたは未適用の変更がある可能性」として扱います。

### Drift Detection で検知できる範囲

このworkflowで検知できるのは、Terraform state に登録されている管理対象リソースの差分です。

検知できる例:

```text
Terraformで作成したStorage AccountのタグをAzure Portalで変更した
Terraformで管理している設定値をAzure Portalで変更した
```

検知できない例:

```text
Terraform管理外のStorage AccountをAzure Portalで作成した
Terraform管理外のResource Groupを作成した
state用Storage Accountにタグを追加した
Terraform stateに登録されていないリソースを変更した
```

このハンズオンでTerraform管理対象なのは、`rg-tf-handson-sandbox-jpe` 内の検証用 Storage Account です。

state用Storage AccountはTerraform管理対象ではありません。

### merge と apply は別物

Pull Request を merge すると、Terraform コードは `main` に入ります。

ただし、Azure 上のリソースが変更されるのは、`terraform apply` が成功した後です。

Environment 承認待ちの状態では、次のようになります。

```text
mainブランチ:
  変更済み

Terraform Apply workflow:
  実行途中

Azure上のリソース:
  まだ変更前

remote state:
  基本的にはapply前の状態
```

## トラブルシュート

### `terraform init` で Tenant ID / Client ID が必要と言われる

エラー例です。

```text
a Tenant ID must be configured when authenticating with OIDC
a Client ID must be configured when authenticating with OIDC
```

`terraform init` の backend config に次が入っているか確認します。

```bash
-backend-config="tenant_id=${{ secrets.AZURE_TENANT_ID }}" \
-backend-config="client_id=${{ secrets.AZURE_CLIENT_ID }}"
```

`terraform-ci.yml`、`terraform-apply.yml`、`terraform-drift-detection.yml` で確認してください。

`terraform-apply.yml` では、`plan` job と `apply` job の両方に必要です。

### Resource Provider 登録で 403 になる

エラー例です。

```text
Terraform does not have the necessary permissions to register Resource Providers.
```

AzureRM Provider v3 を使っている場合は、`provider.tf` に次を設定します。

```hcl
skip_provider_registration = true
```

そのうえで、必要な Resource Provider が登録済みか確認します。

```bash
az provider show \
  --namespace Microsoft.Storage \
  --query "registrationState" \
  -o tsv
```

### PRコメント投稿で 403 になる

エラー例です。

```text
Resource not accessible by integration
```

`terraform-ci.yml` の permissions を確認します。

```yaml
permissions:
  contents: read
  id-token: write
  pull-requests: write
  issues: write
```

また、GitHub リポジトリ側の設定も確認します。

```text
Settings
  → Actions
  → General
  → Workflow permissions
  → Read and write permissions
```

### Codex GitHub ActionでOpenAI API keyエラーになる

Codex GitHub Actionを実行するには、Repository Secret に `OPENAI_API_KEY` が必要です。

GitHubで以下を確認します。

```text
Settings
  → Secrets and variables
  → Actions
  → Secrets
```

`OPENAI_API_KEY` が登録されていることを確認してください。

workflowでは次のように参照します。

```yaml
openai-api-key: ${{ secrets.OPENAI_API_KEY }}
```

### Codex jobで plan.txt が見つからない

Codex jobは、`terraform-plan` jobが保存した artifact から `plan.txt` を取得します。

`terraform-ci.yml` で、plan job側に次のstepがあることを確認します。

```yaml
- name: Upload Terraform plan text
  uses: actions/upload-artifact@v4
  with:
    name: terraform-plan-text-${{ github.event.pull_request.number }}
    path: ${{ env.TF_WORKING_DIR }}/plan.txt
    retention-days: 1
```

また、Codex job側に次のstepがあることを確認します。

```yaml
- name: Download Terraform plan text
  uses: actions/download-artifact@v4
  with:
    name: terraform-plan-text-${{ github.event.pull_request.number }}
    path: codex-input
```

artifact名が一致していないと、Codex jobで `plan.txt` を取得できません。

### Codexの解説がPR本文を反映していない

`Build Codex prompt` stepで、PRタイトルとPR本文を `codex-prompt.md` に追加しているか確認します。

```yaml
env:
  PR_TITLE: ${{ github.event.pull_request.title }}
  PR_BODY: ${{ github.event.pull_request.body }}
```

PR本文が空の場合、Codexには次の文が渡されます。

```text
(No pull request description provided.)
```

その場合、Codexは「PR本文が空のため、意図の確認は限定的」といった説明を行います。

### Secretsに移した値が参照できない

このハンズオンでは、次の値を Repository Secrets として扱います。

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
TF_STATE_STORAGE_ACCOUNT
OPENAI_API_KEY
```

workflowでは、これらを `vars` ではなく `secrets` で参照します。

```yaml
${{ secrets.AZURE_CLIENT_ID }}
${{ secrets.AZURE_TENANT_ID }}
${{ secrets.AZURE_SUBSCRIPTION_ID }}
${{ secrets.TF_STATE_STORAGE_ACCOUNT }}
${{ secrets.OPENAI_API_KEY }}
```

たとえば、Azure loginでは次のように指定します。

```yaml
client-id: ${{ secrets.AZURE_CLIENT_ID }}
tenant-id: ${{ secrets.AZURE_TENANT_ID }}
subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

backend設定では次のように指定します。

```bash
-backend-config="storage_account_name=${{ secrets.TF_STATE_STORAGE_ACCOUNT }}" \
-backend-config="tenant_id=${{ secrets.AZURE_TENANT_ID }}" \
-backend-config="client_id=${{ secrets.AZURE_CLIENT_ID }}"
```

### forkからのPull RequestでSecretsが渡されない

Publicリポジトリで外部forkからPull Requestが作成された場合、GitHub Secretsは通常workflowに渡されません。

この場合、Azure loginやCodex GitHub Actionは失敗する可能性があります。

このハンズオンは、自分のリポジトリ内ブランチからPull Requestを作成する前提です。

### Apply workflow が merge 後に自動起動しない

`terraform-apply.yml` のトリガーを確認します。

```yaml
on:
  push:
    branches:
      - main
    paths:
      - "infra/terraform/**"

  workflow_dispatch:
```

`paths` に一致するファイルが変更されていない場合、push されても Apply workflow は起動しません。

### Drift Detectionで差分があるのにIssueが作成されない

`terraform plan` のログに差分が出ているのに、Summaryで `Terraform plan exit code: 0` になっている場合、`hashicorp/setup-terraform` の Terraform wrapper により、`-detailed-exitcode` の終了コードが正しく取得できていない可能性があります。

`terraform-drift-detection.yml` の `Setup Terraform` に次が入っているか確認します。

```yaml
- name: Setup Terraform
  uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: 1.9.0
    terraform_wrapper: false
```

`terraform_wrapper: false` を設定することで、`terraform plan -detailed-exitcode` の終了コード `0 / 1 / 2` を正しく扱いやすくしています。

### Drift Detectionで変更を検知できない

次を確認してください。

* 手動変更したリソースが Terraform 管理対象か
* 手動変更したStorage Accountが `rg-tf-handson-sandbox-jpe` 内の検証用Storage Accountか
* state用Storage Accountを変更していないか
* `main.tf` に `lifecycle ignore_changes = [tags]` のような設定が入っていないか
* Drift Detection workflowを `main` ブランチのworkflowとして実行しているか

Terraform管理外のリソース変更は、このworkflowでは検知できません。

## 後片付け

このハンズオンでは、destroy workflow は作っていません。

Azure CLI または Azure Portal から確認しながら削除します。

検証用 Storage Account を確認します。

```bash
az storage account list \
  --resource-group rg-tf-handson-sandbox-jpe \
  --query "[].name" \
  -o tsv
```

検証用 Storage Account を削除します。

```bash
az storage account delete \
  --name "<検証用Storage Account名>" \
  --resource-group rg-tf-handson-sandbox-jpe \
  --yes
```

ターゲット Resource Group を削除する場合です。

```bash
az group delete \
  --name rg-tf-handson-sandbox-jpe \
  --yes
```

state 用 Resource Group も不要であれば削除します。

```bash
az group delete \
  --name rg-tfstate-handson-jpe \
  --yes
```

App Registration / Service Principal を削除します。

```bash
az ad app delete --id "<APP_ID>"
```

注意: state 用 Storage Account を削除すると、Terraform state も削除されます。本番では絶対に安易に削除しないでください。

## 発展課題

この構成を理解できたら、次のような発展が考えられます。

* Codexのプロンプトを改善し、解説の粒度を調整する
* Terraform plan JSON を解析して、削除・再作成・公開設定変更などを機械的に検出する
* Codexには「検出結果の説明」に専念させる
* 危険な差分がある場合に、CIを失敗させる仕組みを追加する
* drift detectionのIssue本文にもCodexによる日本語解説を追加する
* tfcmt を使って plan コメントをより見やすくする
* 顧客別・環境別に state key や Resource Group を分ける
* destroy workflow を承認付きで追加する
* bootstrap Terraform と application Terraform を分ける

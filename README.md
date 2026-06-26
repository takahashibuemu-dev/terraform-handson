# Terraform CI/CD + Azure OIDC ハンズオン

このリポジトリは、GitHub Actions と Terraform を使って、Azure 上に検証用 Storage Account を作成するハンズオンです。

主な目的は、Terraform の CI/CD を GitHub Actions で構成し、Azure への認証に Client Secret ではなく OIDC を使う流れを体験することです。

## このハンズオンで学ぶこと

このハンズオンでは、次の内容を扱います。

* Terraform の remote state を Azure Blob Storage に保存する
* GitHub Actions から Azure へ OIDC で認証する
* Pull Request 作成時に `terraform plan` を自動実行する
* Pull Request に Terraform plan の結果をコメントする
* `main` ブランチへの merge 後に Terraform Apply workflow を自動起動する
* GitHub Environment の承認後に `terraform apply` を実行する
* `terraform plan -out=tfplan` で作成した plan ファイルを artifact として apply job に渡す
* Terraform 実行用 Service Principal の権限を Resource Group スコープに絞る

この構成は学習用の最小構成です。本番利用する場合は、権限設計、state保護、レビュー運用、監査、destroy運用などを追加で検討してください。

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
PRにplan結果をコメント
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

## リポジトリ構成

```text
.
├── .github/
│   └── workflows/
│       ├── terraform-ci.yml
│       └── terraform-apply.yml
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
* GitHub Actions Summary に plan 結果を出力
* Pull Request に plan 結果をコメント

この workflow では `terraform apply` は実行しません。

### `.github/workflows/terraform-apply.yml`

`main` ブランチへの push、または手動実行で起動する Apply workflow です。

実行内容は次の通りです。

* `plan` jobで `terraform plan -out=tfplan` を実行
* `tfplan` を artifact として保存
* `apply` jobで GitHub Environment 承認を待つ
* 承認後、artifact から `tfplan` を取得
* `terraform apply tfplan` を実行

通常は、Pull Request を merge するとこの workflow が自動起動します。

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
| `AZURE_CLIENT_ID`          | App Registration の App ID   |
| `AZURE_TENANT_ID`          | Azure Tenant ID             |
| `AZURE_SUBSCRIPTION_ID`    | Azure Subscription ID       |
| `TF_STATE_RESOURCE_GROUP`  | `rg-tfstate-handson-jpe`    |
| `TF_STATE_STORAGE_ACCOUNT` | state 用 Storage Account 名   |
| `TF_STATE_CONTAINER`       | `tfstate`                   |
| `TF_STATE_KEY`             | `demo/sandbox/main.tfstate` |
| `TF_TARGET_RESOURCE_GROUP` | `rg-tf-handson-sandbox-jpe` |
| `LOCATION`                 | `japaneast`                 |

このハンズオンでは Client Secret は使いません。

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

### 5. Terraform CI を確認する

Pull Request 作成後、`Terraform CI` workflow が実行されます。

確認ポイントは次の通りです。

* `terraform init` が成功する
* `terraform fmt -check` が成功する
* `terraform validate` が成功する
* `terraform plan` が成功する
* Pull Request に `Terraform Plan Result` コメントが投稿される

### 6. Pull Request を merge する

Plan の内容に問題がなければ、Pull Request を merge します。

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
-backend-config="tenant_id=${{ vars.AZURE_TENANT_ID }}" \
-backend-config="client_id=${{ vars.AZURE_CLIENT_ID }}"
```

`terraform-ci.yml` と `terraform-apply.yml` の両方で確認してください。

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

* tfcmt を使って plan コメントをより見やすくする
* Terraform plan JSON を解析して危険な差分を検出する
* AI に plan の内容を日本語で要約させる
* drift detection を追加する
* 顧客別・環境別に state key や Resource Group を分ける
* destroy workflow を承認付きで追加する
* bootstrap Terraform と application Terraform を分ける

## 1. 「このハンズオンで学ぶこと」に追記

既存の「## このハンズオンで学ぶこと」の箇条書きに、以下を追加します。

```markdown
* Codex GitHub Action を使って Terraform plan の内容を日本語で解説する
* Pull Request のタイトル・説明文と Terraform plan の内容を比較し、変更意図と差分が合っているかを確認する
* Codex の解説結果を Pull Request コメントとして投稿する
* OpenAI API key を GitHub Secrets で管理する
* Public リポジトリで見せたくないAzure識別子やstate用Storage Account名を GitHub Secrets に移す
```

---

## 2. 「全体像」の図を差し替え

既存の「## 全体像」にあるフロー図を、以下に差し替えます。

````markdown
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
````

````

---

## 3. 「リポジトリ構成」を差し替え

既存の「## リポジトリ構成」を以下に差し替えます。

```markdown
## リポジトリ構成

```text
.
├── .github/
│   ├── workflows/
│   │   ├── terraform-ci.yml
│   │   └── terraform-apply.yml
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
````

````

---

## 4. `.github/workflows/terraform-ci.yml` の説明を差し替え

既存の「### `.github/workflows/terraform-ci.yml`」の説明を、以下に差し替えます。

```markdown
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
````

---

## 5. Codexプロンプトファイルの説明を追加

「各ファイルの役割」の中に、以下を追加します。

````markdown
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
````

これにより、Codexは単にplanを要約するだけでなく、PRで説明されている変更意図と、実際のTerraform planの内容が合っているかも確認します。

````

---

## 6. 「事前に必要なもの」に追記

既存の「## 事前に必要なもの」の箇条書きに、以下を追加します。

```markdown
* OpenAI API key
* GitHub Actions で Codex GitHub Action を実行するための Repository Secret
````

---

## 7. 「GitHub側の設定」を差し替え

既存の「### Repository Variables」を、以下の「Repository Secrets」と「Repository Variables」に差し替えます。

````markdown
### Repository Secrets

GitHub リポジトリで以下を開きます。

```text
Settings
  → Secrets and variables
  → Actions
  → Secrets
````

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

````

---

## 8. 「実行方法」のTerraform CI確認部分を差し替え

既存の「### 5. Terraform CI を確認する」を以下に差し替えます。

```markdown
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
````

---

## 9. 「重要な設計ポイント」にCodex関連を追加

「## 重要な設計ポイント」の中に、以下を追加します。

````markdown
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
````

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

````

---

## 10. 「トラブルシュート」にCodex関連を追加

既存の「## トラブルシュート」に、以下を追加します。

```markdown
### Codex GitHub ActionでOpenAI API keyエラーになる

Codex GitHub Actionを実行するには、Repository Secret に `OPENAI_API_KEY` が必要です。

GitHubで以下を確認します。

```text
Settings
  → Secrets and variables
  → Actions
  → Secrets
````

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

````

---

## 11. 「発展課題」を差し替え

既存の「## 発展課題」を以下に差し替えます。

```markdown
## 発展課題

この構成を理解できたら、次のような発展が考えられます。

* Codexのプロンプトを改善し、解説の粒度を調整する
* Terraform plan JSON を解析して、削除・再作成・公開設定変更などを機械的に検出する
* Codexには「検出結果の説明」に専念させる
* 危険な差分がある場合に、CIを失敗させる仕組みを追加する
* tfcmt を使って plan コメントをより見やすくする
* drift detection を追加する
* 顧客別・環境別に state key や Resource Group を分ける
* destroy workflow を承認付きで追加する
* bootstrap Terraform と application Terraform を分ける
````

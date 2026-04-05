# Extension Factory Lp Deployment Scripts

一键部署和验证 ExtensionLpFactory 合约的脚本集合。

## 📁 脚本说明

### 00_init.sh

**环境初始化脚本**

- 设置网络参数
- 加载账户配置
- 定义常用函数（`cast_call`, `forge_script`, `check_equal`等）
- 初始化 keystore 密码

### one_click_deploy.sh ⭐

**一键部署主脚本**

自动完成以下步骤：

1. 初始化环境
2. 部署 ExtensionLpFactory 合约
3. 验证合约（仅 thinkium70001 网络）
4. 运行部署检查

### v2_one_click_deploy.sh ⭐

**V2 一键部署主脚本**

自动完成以下步骤：

1. 初始化环境
2. 部署 ExtensionLpFactoryV2 合约
3. 验证 V2 合约（仅 thinkium70001 网络）
4. 运行 V2 部署检查

### 03_verify.sh

**合约验证脚本**

- 在区块链浏览器上验证合约源代码
- 仅适用于 thinkium70001 系列网络
- 其他网络会自动跳过

### v2_03_verify.sh

**V2 合约验证脚本**

- 在区块链浏览器上验证 `ExtensionLpFactoryV2`
- 仅适用于 thinkium70001 系列网络
- 其他网络会自动跳过

### 99_check.sh

**部署验证脚本**

检查 ExtensionLpFactory 合约的参数是否正确：

- center address 是否正确设置

### v2_99_check.sh

**V2 部署验证脚本**

检查 `ExtensionLpFactoryV2` 合约的参数是否正确：

- center address 是否正确设置

## 🚀 使用方法

### 方式 1：一键部署（推荐）

```bash
cd script/deploy
source one_click_deploy.sh <network>
```

示例：

```bash
# 部署到 anvil 本地测试网
source one_click_deploy.sh anvil

# 部署到 thinkium70001_public
source one_click_deploy.sh thinkium70001_public

# 部署到 thinkium70001_public_test
source one_click_deploy.sh thinkium70001_public_test
```

### 方式 1.1：V2 一键部署

```bash
cd script/deploy
source v2_one_click_deploy.sh <network>
```

示例：

```bash
source v2_one_click_deploy.sh anvil
source v2_one_click_deploy.sh thinkium70001_public
source v2_one_click_deploy.sh thinkium70001_public_test
```

### 方式 2：分步部署

```bash
cd script/deploy

# Step 1: 初始化环境
source 00_init.sh <network>

# Step 2: 部署合约
forge_script_deploy_extension_factory_lp

# Step 3: 加载部署地址
source $network_dir/address.extension.lp.params

# Step 4: 验证合约（可选，仅 thinkium 网络）
source 03_verify.sh

# Step 5: 检查部署
source 99_check.sh
```

### 方式 3：V2 分步部署

```bash
cd script/deploy

# Step 1: 初始化环境
source 00_init.sh <network>

# Step 2: 部署 V2 合约
source v2_01_deploy_extension_lp_factory.sh

# Step 3: 加载部署地址
source $network_dir/address.extension.lp.v2.params

# Step 4: 验证合约（可选，仅 thinkium 网络）
source v2_03_verify.sh

# Step 5: 检查部署
source v2_99_check.sh
```

## 📋 前置条件

1. **已部署 LOVE20 Extension Center**

   - 确保 `script/network/<network>/address.extension.center.params` 文件包含 centerAddress

2. **配置账户文件（可选）**

   - `script/network/<network>/.account` 文件包含 keystore 配置
   - 如果没有此文件，需要手动设置 KEYSTORE_ACCOUNT 和 ACCOUNT_ADDRESS

3. **网络配置**
   - `script/network/<network>/network.params` 包含 RPC URL 等信息

## 📝 部署后文件

部署成功后，合约地址会写入：

```
script/network/<network>/address.extension.lp.params
```

内容格式：

```bash
lpFactoryAddress=0x...
```

V2 部署成功后，合约地址会写入：

```
script/network/<network>/address.extension.lp.v2.params
```

内容格式：

```bash
lpFactoryV2Address=0x...
```

## 🔍 查看可用网络

```bash
cd script/deploy
ls ../network/
```

## ⚠️ 注意事项

1. **密码管理**：如果使用 keystore，首次运行时需要输入密码，密码会保存在当前 shell 会话中

2. **Gas 设置**：默认 gas-price 为 5 Gwei，gas-limit 为 50M，可在 `00_init.sh` 中调整

3. **验证失败**：如果合约验证失败，不影响部署成功，可以后续手动验证

4. **检查失败**：如果部署检查失败，说明合约参数配置有误，需要重新部署

## 📊 输出示例

```
=========================================
  One-Click Deploy Extension Factory Lp
  Network: anvil
=========================================

[Step 1/4] Initializing environment...
✓ Environment initialized

[Step 2/4] Deploying ExtensionLpFactory...
✓ Extension Factory Lp deployed at: 0x59b670e9fA9D0A427751Af201D676719a970857b

[Step 3/4] Skipping contract verification (not a thinkium network)

[Step 4/4] Running deployment checks...
=========================================
Verifying Extension Factory Lp Configuration
=========================================
✓ Center address
  Expected: 0x5fbdb2315678afecb367f032d93f642f64180aa3
  Actual:   0x5fbdb2315678afecb367f032d93f642f64180aa3

=========================================
✓ All checks passed (1/1)
=========================================

=========================================
✓ Deployment completed successfully!
=========================================
Extension Factory Lp Address: 0x59b670e9fA9D0A427751Af201D676719a970857b
Network: anvil
=========================================
```

## 🛠️ 故障排除

### 问题：找不到网络

```bash
Error: Network parameter is required.
```

**解决**：检查网络名称是否正确，确保 `script/network/<network>` 目录存在

### 问题：Extension Center 地址未找到

```bash
Error: centerAddress not found
```

**解决**：确保先部署 LOVE20ExtensionCenter，并且 `address.extension.center.params` 文件包含 centerAddress

### 问题：部署检查失败

```bash
✗ N check(s) failed
```

**解决**：检查链上合约状态，可能需要重新部署

## 📚 相关文件

- 部署脚本：`script/DeployExtensionLpFactory.s.sol`
- V2 部署脚本：`script/DeployExtensionLpFactoryV2.s.sol`
- 合约源码：`src/ExtensionLpFactory.sol`
- V2 合约源码：`src/ExtensionLpFactoryV2.sol`
- Extension 合约：`src/ExtensionLp.sol`
- Foundry 配置：`foundry.toml`

# Self-host CUDA

该示例用于运行 Ubuntu 24.04、CUDA 12.8 和 PyTorch 开发环境。宿主机需要安装 NVIDIA 驱动、Docker Engine、Docker Compose v2 和 NVIDIA Container Toolkit。

## 启动

```bash
cp .env.example .env
# 编辑 .env，设置首次登录密码或 SSH 公钥。
mkdir -p projects data
docker compose up -d
ssh -p 2222 root@localhost
```

首次启动必须提供以下任一凭据：

- `INITIAL_ROOT_PASSWORD`
- `INITIAL_ROOT_PASSWORD_FILE`
- `SSH_PUBLIC_KEY`
- `SSH_AUTHORIZED_KEYS_FILE`

`INITIAL_ROOT_PASSWORD` 只在状态卷尚未初始化时生效。首次启动后，密码 hash 会保存在 `self-host-state` 卷中，并在容器重建时恢复；之后修改该环境变量不会重置密码。由于环境变量可通过 `docker inspect` 查看，首次初始化成功后应从 `.env` 删除密码并执行：

```bash
docker compose up -d --force-recreate
```

如需避免把初始密码放入环境变量，可取消 `compose.yaml` 中密码文件挂载的注释，并设置 `INITIAL_ROOT_PASSWORD_FILE=/run/secrets/root-password`。

推荐使用 SSH 公钥。可以直接设置 `SSH_PUBLIC_KEY`，也可以取消 `compose.yaml` 中公钥文件挂载的注释，并在 `.env` 中设置 `SSH_AUTHORIZED_KEYS_FILE=/run/secrets/authorized_keys`。

## GPU 和资源限制

默认映射所有 GPU，并限制为 16 CPU、64 GiB 内存、4096 PID 和 16 GiB `/dev/shm`。可在 `.env` 中调整 `GPU_COUNT`、`CPU_LIMIT`、`MEMORY_LIMIT`、`PIDS_LIMIT` 和 `SHM_SIZE`。

只使用一张 GPU：

```dotenv
GPU_COUNT=1
NVIDIA_VISIBLE_DEVICES=0
```

使用指定的多张 GPU：

```dotenv
GPU_COUNT=all
NVIDIA_VISIBLE_DEVICES=0,2
```

## 持久化范围

默认持久化：

- `/root`：用户配置、虚拟环境、代码和缓存。
- `/workspace`：工作区。
- `/var/lib/self-host`：初始密码 hash 和 SSH host keys。
- `/workspace/projects`、`/data`：宿主机绑定目录，便于备份和共享数据。

基础 Python/PyTorch 环境位于 `/opt/venv`，镜像更新后可随镜像一起升级。需要长期保留的自定义 Python 环境，建议创建在 `/root/.venvs` 或 `/workspace`。

## 不建议持久化整个容器

容器 writable layer 在普通重启时会保留，但执行 `docker compose down` 后重建容器就会丢失。可以通过 `docker commit` 保存整个 root filesystem，但存在以下缺点：

- 无法从 Dockerfile 重现，难以审计和回滚。
- 镜像容易持续膨胀，并包含缓存、日志和临时文件。
- volume 内容不会被 `docker commit` 保存。
- 可能把密码、SSH key、token 或数据意外写入镜像层。
- 系统包和 Python 包版本来源不清晰，后续更新容易产生漂移。

因此示例选择持久化用户目录、工作区和初始化状态；需要永久增加系统软件时，应创建派生 Dockerfile。

## 常用命令

```bash
docker compose exec workspace nvidia-smi
docker compose exec workspace python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'
docker compose exec workspace bash
docker compose logs -f workspace
```

启动 JupyterLab：

```bash
docker compose exec workspace \
  jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

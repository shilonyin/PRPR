# MoeCatnip

一个 Moebooru（yande.re / konachan）壁纸客户端，从 Windows UWP 重写为 Flutter 桌面版。
原版 UWP 源码保留在 [`PRPR/`](PRPR/) 与 [`Imaging/`](Imaging/) 供参考，
Flutter 重写版在 [`app/`](app/)。

构建与运行见 [`app/README.md`](app/README.md)，迁移记录见 [`MIGRATION.md`](MIGRATION.md)。

## 人脸检测模型的来源

「不切脸裁剪」用的分类器是 [`app/assets/lbpcascade_animeface.xml`](app/assets/lbpcascade_animeface.xml)。
它不是本项目的产物，而是 nagadomi 用动漫人脸图片训练出来的 LBP 级联模型，2011 年首次发布。

| | |
| --- | --- |
| 作者 | nagadomi |
| 原始地址 | <http://anime.udp.jp/data/lbpcascade_animeface.xml> |
| 代码仓库 | <https://github.com/nagadomi/lbpcascade_animeface> |
| 许可 | MIT，Copyright (C) 2011 nagadomi |

MIT 许可证要求分发时保留版权声明，完整原文就写在级联文件头部的注释里，随文件一起分发，请勿删除。

## 致谢

- **nagadomi** — 上面那个人脸级联模型。没有它，「不切脸裁剪」就只能靠猜。
- **shilonyin** — 原 PRPR 项目作者，功能设计、交互流程与裁剪算法都来自他的 UWP 原版。
- **yande.re / konachan** — 图片、标签、评分与每日榜单的来源，以及给它们打标签的社区志愿者。
- **OpenCV** 与 Dart 绑定 [opencv_dart](https://github.com/rainyl/opencv_dart) — 图像处理与级联推理。
- **Flutter / Dart** 及 pub 上的各第三方包，许可证全文可在应用内「关于 → 开源许可」查看。

## 关于原版

原 UWP 应用已被微软从商店下架：

> ~~https://www.microsoft.com/store/p/prpr/9nblggh4stnm~~

The app has been removed from the store by Microsoft.
You can download an offline package by other developers:
<https://github.com/AmazingDM/PRPR/releases/tag/2.7>

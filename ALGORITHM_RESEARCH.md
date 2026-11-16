# 相位型 SLM 全息图算法调研与本工程诊断

更新：2026-11-16。范围：单片相位型 LCoS SLM 的傅里叶面图案、多焦点阵列和连续环形/平顶光束。以下文献是针对不同目标的算法依据，不存在对所有光路都最优的单一算法。

## 优化前的程序诊断（历史基线）

- `generate_slm_hologram.m` 以均匀入射振幅和理想 FFT 作为前向模型，使用 GS 或逐焦点功率反馈的 WGS。输入光束实际高斯包络、器件像素孔径、相邻像素串扰和相机响应均未建模。
- 程序在叠加载波、附加相位、背景补偿和灰度量化**之前**计算 `reconstruction` 与 `final_normalized_mse`。因此这两个量只评估中间连续相位，不能评价最终 `hologram.png`。当前 `output/metadata.json` 的 8 px 横向载波会将一阶图案移约 1920/8 = 240 个傅里叶采样点。
- 全图、峰值归一化 MSE 容易被黑色背景掩盖。当前环形目标中 `target_used.png > 0.1` 的像素只占 3.90%；元数据 MSE 为 0.001616。对最终灰度文件按**理想线性 0–2π LUT**做独立 FFT，未对齐载波时全图 MSE 为 0.02282；平移目标 240 px 后全图 MSE 为 0.001628，而环形信号区 MSE 为 0.04136。这只是数值核查，不代表真实 SLM 的光学测量。
- 当前输出参数为 1030 nm、8 µm 像元、100 次 GS、无实测 LUT。波长和像元间距只是配置值；缺少实际器件型号、入射光束轮廓、偏振、傅里叶透镜焦距及实拍图，无法把数值误差直接归因于某一项硬件误差。
- 启用 `active_region_enabled` 时，计算把区域外振幅置零，导出的相位图却只让区域外回到基础相位。若器件区域外仍被照亮，它仍会反射/透射光；此时数值孔径与物理孔径不一致。
- 原有 `selftest` 在 MATLAB 2025b 中通过，但未验证最终灰度图的数值光学重建。

## 已实施的算法改进与同条件结果

- 增加 MRAF，允许连续目标在目标区域及守护区约束振幅，释放其余区域的振幅；参数化连续环与平顶目标在自动模式下选用 MRAF，多焦点阵列仍选用 WGS。对应下文 A2、A3、A4 的研究路线。
- 数值预览和最终指标现从**导出的 8 位灰度码**及 LUT 反算相位，纳入载波、附加相位、背景补偿和可选实测入射振幅；另保存带载波的完整傅里叶面。没有实测 LUT 时，反算使用理想线性相位响应。
- 增加信号区最佳比例拟合后的归一化 RMSE、信号区功率比例，以及量化前诊断 MSE；`selftest` 已加入灰度回算一致性、MRAF 对照与非均匀入射光测试。
- 对同一个 `output/target_used.png` 环形目标、1080×1920 分辨率、100 次迭代、随机种子 42、8 px 横向载波及相同理想线性 LUT，重新生成 GS 的信号区 nRMSE 为 **0.138344**、信号区功率比例为 **0.855951**；MRAF 分别为 **0.048881** 与 **0.824990**。信号区 nRMSE 降低约 **64.7%**，代价是功率比例降低约 **3.10 个百分点**。两组最终灰度文件分别在 `output_gs_baseline/hologram.png` 与 `output_optimized/hologram.png`。原始旧文件 `output/hologram.png` 的独立复算值为 0.137800 和 0.855500，可供历史参照，但正式同输入比较使用重新生成的 GS。
- 以上仅为同一理想傅里叶模型中的数值结果。实测 LUT、相机图、真实入射振幅与像差尚未提供，不能据此推断实验光斑误差也降低 64.7%。后续代码审查、参数扫描与零级分析见 [ALGORITHM_AUDIT.md](ALGORITHM_AUDIT.md)。

## 文献给出的可用路线

| 需求 | 有据可循的方法 | 对本工程的具体含义 |
| --- | --- | --- |
| 连续环、平顶、任意强度区的平滑度 | Pasienski 与 DeMarco 的 mixed-region amplitude freedom（MRAF）在信号区约束强度，在噪声区释放振幅自由度；Schroff 等进一步用共轭梯度、相机反馈和像素串扰模型改善连续光势。 | 增加可配置的信号区、缓冲区、噪声区以及效率/粗糙度权衡；连续目标不要仅靠全平面 GS。 |
| 多焦点功率一致性 | 增强 GS/WGS 在阵列任务中结合逐点反馈、零填充与相位连续性。 | 保留 WGS 基线，但评价每个焦点的积分功率、均匀度、效率与串扰，并在**最终灰度图**上复算。 |
| 一般图像和环形图案的散斑 | 直接优化 SLM 相位的梯度法允许设置目标区域损失、背景泄漏、效率、平滑度等目标。 | 先在 MATLAB 中实现可复现的相位梯度/共轭梯度基线，并与 GS、MRAF 在相同传播模型和评价区比较；仅增加迭代次数没有针对性。 |
| 数值好、实拍差 | Camera-in-the-loop（CITL）把实拍图用于反馈；2025 年的傅里叶全息研究还讨论了输入振幅优化；2026 年预印本进一步提出可微的完整光路数字孪生。 | 先采集光束、LUT、零级、畸变和图案实拍；再用相机反馈或标定后的前向模型优化。数字孪生为前沿方向，当前不应在缺测量数据时直接套用。 |
| 近场或多深度目标 | 角谱传播和深度可调优化适用于非傅里叶焦平面；2025 年 4K 工作展示物理约束神经算子处理可变深度。 | 只有确认目标不是外部透镜的单一后焦面时，才把 FFT 改为角谱/菲涅耳传播并加入多平面损失；不能将傅里叶面与近场模型混用。 |

## 建议的实现顺序与验收量

1. **完善测量链**：现已从导出的 8 位灰度与 LUT 回推相位，并纳入可选入射振幅与完整载波；下一步采集实测 LUT、真实孔径和相机坐标映射，分别核对零级和一阶坐标。
2. **扩展评价指标**：现已报告信号区归一化 RMSE、信号区功率比例与最终灰度图全图 MSE；下一步增加局部散斑对比度、环向均匀度和背景泄漏比。阵列继续报告各焦点积分功率均匀度。
3. **按目标分算法**：离散阵列保留 WGS，连续环和平顶已加入 MRAF；后续可加入梯度/共轭梯度基线，并固定随机种子、目标图、孔径和传播模型做消融比较。
4. **引入设备标定**：测入射振幅、灰度—相位 LUT、相机与傅里叶坐标映射、像差和零级。若仍出现光学与模拟差异，再评估像素串扰模型和 CITL。

验收必须同时比较 `target_used.png`、最终 `hologram.png` 的数值重建和相机实拍；所有光学指标使用同一信号区域及功率归一化规则。没有实拍图时，只能确认数值算法和输出链一致，不能宣称解决实验光斑问题。

## 扩展阅读结论

文献覆盖 1982–2026 年的 30 项原始研究和 1 项综述。下表的“适用”只表示与本工程模型和目标的关系，不表示不同论文报道的精度、效率可直接横向比较：光源、SLM、有效孔径、目标大小、测量区和归一化方式都不同。2026 年 arXiv 条目明确标为预印本。

| 证据组 | 文献共同指出的技术问题 | 对本工程的判断 |
| --- | --- | --- |
| A：单傅里叶面、连续图案 | GS 的全平面强度约束限制信号区精度；MRAF/OMRAF、共轭梯度和相机反馈改善连续光势，但精度与效率存在权衡。 | **优先**用于当前环形图案。先复现实测或数值环向均匀度，再比较算法。 |
| B：离散焦点阵列 | 加权迭代、焦点功率反馈和相位连续性改善阵列均匀度；离散点假设不能直接移植到连续环。 | 保留 WGS，单独开发并验收。 |
| C：设备前向模型 | 入射光斑、灰度相位响应、空间非均匀性、像素串扰、像素孔径和像差均可造成仿真与实物偏差。 | 先标定可观测项，再考虑更复杂优化器。 |
| D：学习与多深度 | 神经网络主要解决重复目标或多平面的生成速度、深度适应；需要训练数据或可信前向模型。 | 当前单张、单焦平面环形图案**后置**。 |

尤其值得注意的是：Gaunt 与 Hadzibabic 的 OMRAF 文献在其光路中发现超出简单傅里叶近似有帮助；Schroff 等在另一套光路中测试角谱法代替 FFT，却没有观察到误差改善。因此是否改传播算子应由实际光路、焦面位置及测量结果决定，不能把角谱法视作普遍升级。

### A. 连续图案、环形光场与通用相位优化（10 篇）

| # | 文献 | 可借鉴点 |
| --- | --- | --- |
| A1 | Fienup, *Phase retrieval algorithms: a comparison*, Applied Optics 21, 2758–2769 (1982), [DOI](https://doi.org/10.1364/AO.21.002758) | 迭代投影、误差下降法和梯度法的基础；提供 GS 对照的理论背景。 |
| A2 | Pasienski & DeMarco, *A high-accuracy algorithm for designing arbitrary holographic atom traps*, Optics Express 16, 2176–2190 (2008), [论文](https://arxiv.org/abs/0712.0794) | MRAF：信号区受约束，噪声区给振幅自由度；直接对应连续环和平顶图案。 |
| A3 | Gaunt & Hadzibabic, *Robust Digital Holography For Ultracold Atom Trapping*, Scientific Reports 2, 721 (2012), [DOI](https://doi.org/10.1038/srep00721) | OMRAF：为暗背景加入受控偏置以降低涡旋停滞；讨论何时需更准确传播模型。 |
| A4 | Bruce et al., *Feedback-enhanced algorithm for aberration correction of holographic atom traps*, Journal of Physics B 48, 115303 (2015), [DOI](https://doi.org/10.1088/0953-4075/48/11/115303) | 将 MRAF 与相机反馈结合，给出环形图案实验中信号区 RMS 和环向强度曲线。 |
| A5 | Bowman et al., *High-fidelity phase and amplitude control of phase-only computer generated holograms using conjugate gradient minimisation*, Optics Express 25, 11692–11700 (2017), [DOI](https://doi.org/10.1364/OE.25.011692) | 在指定测量区用共轭梯度优化目标场；适合加入信号区损失。 |
| A6 | Holland et al., *Benchmarking modern algorithms to holographically create optical tweezers for laser-cooled atoms*, Journal of Modern Optics 65, 2133–2141 (2018), [DOI](https://doi.org/10.1080/09500340.2018.1499978) | 在统一任务中比较算法速度、精度和效率；说明评价协议比单一 MSE 更有用。 |
| A7 | Aharoni & Shoham, *Phase-controlled, speckle-free holographic projection with applications in precision optogenetics*, Neurophotonics 5, 025004 (2018), [DOI](https://doi.org/10.1117/1.NPh.5.2.025004) | GSW-PC 同时控制相位与振幅，主要验证一维和体图案；可借鉴散斑控制，不直接承诺二维环同样效果。 |
| A8 | Liu & Takaki, *Optimization of Phase-Only Computer-Generated Holograms Based on the Gradient Descent Method*, Applied Sciences 10, 4283 (2020), [DOI](https://doi.org/10.3390/app10124283) | 直接针对傅里叶相位全息的强度损失优化，可作 MATLAB 梯度基线。 |
| A9 | Schroff et al., *Accurate holographic light potentials using pixel crosstalk modelling*, Scientific Reports 13, 3252 (2023), [DOI](https://doi.org/10.1038/s41598-023-30296-6) | 共轭梯度、实测入射场、像素串扰、涡旋处理和相机反馈；论文包含高斯环目标。 |
| A10 | Zhao et al., *Phase-probability shaping for speckle-free holographic lithography*, Nature Communications 16, 9318 (2025), [DOI](https://doi.org/10.1038/s41467-025-64554-0) | 研究相位分布与散斑的关系；实验使用超表面及无透镜光刻，属于探索性参考，不能直接照搬其性能指标。 |

### B. 多焦点与加权 GS（6 篇）

| # | 文献 | 可借鉴点 |
| --- | --- | --- |
| B1 | Di Leonardo, Ianni & Ruocco, *Computer generation of optimal holograms for optical trap arrays*, Optics Express 15, 1913–1922 (2007), [DOI](https://doi.org/10.1364/OE.15.001913) | 加权优化阵列效率和均匀度的早期原始研究。 |
| B2 | Tamura et al., *Highly uniform holographic microtrap arrays for single atom trapping using a feedback optimization of in-trap fluorescence measurements*, Optics Express 24, 8132–8141 (2016), [DOI](https://doi.org/10.1364/OE.24.008132) | 光斑强度与实际陷阱测量的双层反馈；强调数值均匀度不等于实验均匀度。 |
| B3 | H. Kim et al., *Gerchberg-Saxton algorithm for fast and efficient atom rearrangement in optical tweezer traps*, Optics Express 27, 2184–2196 (2019), [DOI](https://doi.org/10.1364/OE.27.002184) | 零填充、加权反馈及连续帧的相位延续；当前静态图仅需前两项。 |
| B4 | D. Kim & Englund, *Large-scale uniform optical focus array generation with a phase spatial light modulator*, Optics Letters 44, 3178 (2019), [DOI](https://doi.org/10.1364/OL.44.003178) | 抑制迭代中的不需要相位旋转，并对大阵列进行自适应校正。 |
| B5 | Gupta & Ravindran, *Laser intensity mapping across a spatial light modulator to generate uniform and aberration-free focal spots*, Optics Communications 530, 129187 (2023), [DOI](https://doi.org/10.1016/j.optcom.2022.129187) | 直接测入射光束位置和振幅；可以替换程序的均匀入射振幅假设。 |
| B6 | Huang et al., *Phase-Stable Hologram Updates for Large-Scale Neutral-Atom Array Reconfiguration* (2026), [arXiv 预印本](https://arxiv.org/abs/2604.04600) | 多帧阵列刷新时约束相位连续性；当前静态输出暂不需要。 |

### C. 标定、真实前向模型与相机闭环（10 篇）

| # | 文献 | 可借鉴点 |
| --- | --- | --- |
| C1 | Engström et al., *Calibration of spatial light modulators suffering from spatially varying phase response*, Optics Express 21, 16086–16103 (2013), [DOI](https://doi.org/10.1364/OE.21.016086) | 全屏统一 LUT 可能不足；相位响应可随位置变化。 |
| C2 | Reichelt, *Spatially resolved phase-response calibration of liquid-crystal-based spatial light modulators*, Applied Optics 52, 2610–2618 (2013), [DOI](https://doi.org/10.1364/AO.52.002610) | 区域化相位响应测量与灰度重映射。 |
| C3 | Moser, Ritsch-Marte & Thalhammer, *Model-based compensation of pixel crosstalk in liquid crystal spatial light modulators*, Optics Express 27, 25046–25063 (2019), [DOI](https://doi.org/10.1364/OE.27.025046) | 相邻像素的边缘电场使实际相位偏离理想逐像素常数模型。 |
| C4 | Shen et al., *An open-source, accurate, and iterative calibration method for liquid-crystal-based spatial light modulators*, Optics Communications 495, 127108 (2021), [DOI](https://doi.org/10.1016/j.optcom.2021.127108) | 实测灰度—相位 LUT 的迭代标定流程。 |
| C5 | Peng et al., *Neural Holography with Camera-in-the-loop Training*, ACM Transactions on Graphics 39(6), 185 (2020), [DOI](https://doi.org/10.1145/3414685.3417802) | 直接优化相位与相机闭环，分析理想模型和实物偏差。 |
| C6 | Chakravarthula et al., *Learned Hardware-in-the-loop Phase Retrieval for Holographic Near-Eye Displays*, ACM Transactions on Graphics 39(6), 186 (2020), [DOI](https://doi.org/10.1145/3414685.3417846) | 学习硬件误差模型；针对近眼显示，迁移需重新标定。 |
| C7 | Yeom, Hong & Park, *High-quality phase-only Fourier hologram generation with camera-in-the-loop*, Optics Express 33, 6615–6628 (2025), [DOI](https://doi.org/10.1364/OE.540114) | 对傅里叶光路进行实拍反馈，并讨论输入振幅优化。 |
| C8 | Singh, Wojcik & Wilkinson, *Camera-in-the-loop gradient descent hologram generation for Fraunhofer diffraction*, Optics Express (2026), [同行评审接受稿](https://www.repository.cam.ac.uk/items/f04a7e74-cf68-42d1-8bf4-9752aab57e1d) | 比较理想 FFT 与含像素孔径、重建带宽的模型；量化每目标相机采集成本。 |
| C9 | Wojcik et al., *Digital twin for full field-of-view Fraunhofer holographic patterning* (2026), [arXiv 预印本](https://arxiv.org/abs/2610.02518) | 联合标定入射场、瞳孔、杂散光、串扰和相机；属当前最贴近完整实物模型的研究方向。 |
| C10 | *Zero-Order Diffraction Suppression in Full Field-of-View Computer Generated Holography: A Camera In the Loop Interferometric Approach* (2026), [arXiv 预印本](https://arxiv.org/abs/2601.20376) | 针对零级的干涉抵消；需要额外光路，当前先测零级再决定是否适用。 |

### D. 多深度、速度与评价函数（4 篇原始研究 + 1 篇综述）

| # | 文献 | 可借鉴点 |
| --- | --- | --- |
| D1 | Eybposh et al., *DeepCGH: 3D computer-generated holography using deep learning*, Optics Express 28, 26636–26650 (2020), [DOI](https://doi.org/10.1364/OE.399624) | 多三维目标重复生成时的速度方向，当前单张环形图不需要先训练网络。 |
| D2 | Shi, Li & Matusik, *End-to-end learning of 3D phase-only holograms for holographic display*, Light: Science & Applications 11, 247 (2022), [DOI](https://doi.org/10.1038/s41377-022-00894-6) | 多深度学习与设备校准，适用前提是明确 3D 任务。 |
| D3 | *Perceptually motivated loss functions for computer generated holographic displays*, Scientific Reports 12, 7709 (2022), [DOI](https://doi.org/10.1038/s41598-022-11373-8) | 展示损失函数会改变结果；其感知质量指标面向显示，不应替代光场均匀度、功率效率。 |
| D4 | Liu et al., *Propagation-adaptive 4K computer-generated holography using physics-constrained spatial and Fourier neural operator*, Nature Communications 16, 7761 (2025), [DOI](https://doi.org/10.1038/s41467-025-62997-z) | 深度可变的 4K 生成；仅在明确近场或多平面需求后考虑。 |
| D5 | *Non-convex optimization for inverse problem solving in computer-generated holography*, Light: Science & Applications 13, 158 (2024), [综述](https://www.nature.com/articles/s41377-024-01446-w) | 用于了解优化问题全貌；具体工程结论仍以上述原始实验为依据。 |

### 由文献导出的比较方案

固定目标图、SLM 孔径、入射振幅、载波、随机种子与计算预算，分别生成 GS、MRAF/OMRAF、共轭梯度三组最终 8 位灰度图。连续环形目标报告环向平均强度的变异系数、环宽误差、信号区归一化 RMSE、信号区功率比例、零级峰值与背景泄漏；多焦点目标另报告逐点积分功率分布和最弱/最强比。仿真评估必须从最终灰度图和实测 LUT 回推；实拍评价必须做相机坐标配准、暗场扣除与线性响应核对。文献中的百分比不能作为本设备尚未测量时的验收承诺。

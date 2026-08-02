// 世界地图布局配置：坐标全部来自素材实测（scripts/_grid 网格校验）
export interface MapDef {
  key: string;
  width: number;
  height: number;
  groundY: number;      // 行走线（脚底 y）
  zones: { id: string; x0: number; x1: number }[]; // 区域 x 范围
}

export const MAP_MAIN = 'main';
export const MAP_MINE = 'mine';
export const MAP_ACADEMY = 'academy';

export const MAPS: Record<string, MapDef> = {
  main: {
    key: MAP_MAIN,
    width: 3072,
    height: 419,
    groundY: 0, // 主世界分区行走线见 MAIN_GROUND
    zones: [
      { id: 'saltlake', x0: 0, x1: 1024 },
      { id: 'grassland', x0: 1024, x1: 2048 },
      { id: 'camp', x0: 2048, x1: 3072 },
    ],
  },
  mine: {
    key: MAP_MINE,
    width: 1024,
    height: 368,
    groundY: 305,
    zones: [{ id: 'mine', x0: 0, x1: 1024 }],
  },
  academy: {
    key: MAP_ACADEMY,
    width: 1024,
    height: 420,
    groundY: 345,
    zones: [{ id: 'academy', x0: 0, x1: 1024 }],
  },
};

// 主世界分区行走线（素材实测）与接缝过渡带宽
export const MAIN_GROUND: { x0: number; y: number }[] = [
  { x0: 0, y: 295 },     // 盐湖
  { x0: 1024, y: 210 },  // 草原
  { x0: 2048, y: 265 },  // 营地
];
export const SEAM_BLEND = 140; // 接缝过渡带半宽

export function mainGroundY(x: number): number {
  // 分段线性插值，接缝处平滑过渡
  for (let i = 0; i < MAIN_GROUND.length - 1; i++) {
    const a = MAIN_GROUND[i];
    const b = MAIN_GROUND[i + 1];
    if (x < b.x0 + SEAM_BLEND || i === MAIN_GROUND.length - 2) {
      if (x <= a.x0 + SEAM_BLEND || i === 0 && x < a.x0 + SEAM_BLEND) {
        if (x < b.x0 - SEAM_BLEND) return a.y;
      }
      if (x >= b.x0 - SEAM_BLEND && x <= b.x0 + SEAM_BLEND) {
        const t = (x - (b.x0 - SEAM_BLEND)) / (2 * SEAM_BLEND);
        return a.y + (b.y - a.y) * t;
      }
      if (x < b.x0 - SEAM_BLEND) return a.y;
      return b.y;
    }
  }
  return MAIN_GROUND[MAIN_GROUND.length - 1].y;
}

export function groundY(mapKey: string, x: number): number {
  if (mapKey === MAP_MAIN) return mainGroundY(x);
  return MAPS[mapKey].groundY;
}

// 主世界三张背景图的拼接（图宽 1024）
export const MAIN_SEGMENTS = [
  { img: 'map_saltlake', x: 0 },
  { img: 'map_grassland', x: 1024 },
  { img: 'map_camp', x: 2048 },
];

// 穿梭点
export interface TravelPoint {
  id: string;
  map: string;      // 所在地图
  x: number;
  toMap: string;    // 目标地图
  toX: number;      // 目标落点 x
  label: string;    // 提示（走 ui_strings 之外的固定设施，用 tips 或短语；路牌类）
  promptKey: string;
}

export const TRAVEL_POINTS: TravelPoint[] = [
  { id: 'to_mine', map: MAP_MAIN, x: 1990, toMap: MAP_MINE, toX: 120, label: 'mine', promptKey: 'prompt_interact' },
  { id: 'mine_exit', map: MAP_MINE, x: 60, toMap: MAP_MAIN, toX: 1960, label: 'grassland', promptKey: 'prompt_interact' },
  { id: 'to_academy', map: MAP_MAIN, x: 2130, toMap: MAP_ACADEMY, toX: 120, label: 'academy', promptKey: 'prompt_interact' },
  { id: 'academy_exit', map: MAP_ACADEMY, x: 60, toMap: MAP_MAIN, toX: 2160, label: 'camp', promptKey: 'prompt_interact' },
];

// 出生点
export const SPAWN_DEFAULT = { map: MAP_MAIN, x: 1500 };  // 草原
export const SPAWN_BED = { map: MAP_MAIN, x: 2268 };      // 营地床边
export const SPAWN_ACADEMY_GATE = { map: MAP_ACADEMY, x: 150 };

// 采集物定义（世界坐标，主世界含拼接偏移）
export interface CollectableDef {
  id: string;         // 实体 id（唯一）
  substanceId: string;
  map: string;
  x: number;
  y: number;          // 相对地面抬高（浮空感）
}

export const COLLECTABLES: CollectableDef[] = [
  // 草原：O₂ 光球（贴地漂浮可及）、C、木棒
  { id: 'g_o2_1', substanceId: 'o2', map: MAP_MAIN, x: 1180, y: 40 },
  { id: 'g_o2_2', substanceId: 'o2', map: MAP_MAIN, x: 1400, y: 35 },
  { id: 'g_o2_3', substanceId: 'o2', map: MAP_MAIN, x: 1650, y: 42 },
  { id: 'g_o2_4', substanceId: 'o2', map: MAP_MAIN, x: 1880, y: 38 },
  { id: 'g_c_1', substanceId: 'c', map: MAP_MAIN, x: 1260, y: 0 },
  { id: 'g_c_2', substanceId: 'c', map: MAP_MAIN, x: 1560, y: 0 },
  { id: 'g_c_3', substanceId: 'c', map: MAP_MAIN, x: 1830, y: 0 },
  { id: 'g_stick_1', substanceId: 'stick', map: MAP_MAIN, x: 1160, y: 0 },
  { id: 'g_stick_2', substanceId: 'stick', map: MAP_MAIN, x: 1520, y: 0 },
  { id: 'g_stick_3', substanceId: 'stick', map: MAP_MAIN, x: 1920, y: 0 },
  // 盐湖：粗盐
  { id: 's_salt_1', substanceId: 'crude_salt', map: MAP_MAIN, x: 160, y: 0 },
  { id: 's_salt_2', substanceId: 'crude_salt', map: MAP_MAIN, x: 380, y: 0 },
  { id: 's_salt_3', substanceId: 'crude_salt', map: MAP_MAIN, x: 620, y: 0 },
  { id: 's_salt_4', substanceId: 'crude_salt', map: MAP_MAIN, x: 850, y: 0 },
  // 营地试剂架（合成台左侧一字排开，高度可及）：hcl/naoh/caoh2/activated_carbon/soap_water/nahco3
  { id: 'c_hcl', substanceId: 'hcl', map: MAP_MAIN, x: 2230, y: 40 },
  { id: 'c_naoh', substanceId: 'naoh', map: MAP_MAIN, x: 2260, y: 40 },
  { id: 'c_caoh2', substanceId: 'caoh2', map: MAP_MAIN, x: 2290, y: 40 },
  { id: 'c_carbon', substanceId: 'activated_carbon', map: MAP_MAIN, x: 2320, y: 40 },
  { id: 'c_soap', substanceId: 'soap_water', map: MAP_MAIN, x: 2350, y: 40 },
  { id: 'c_nahco3', substanceId: 'nahco3', map: MAP_MAIN, x: 2380, y: 40 },
  // 矿洞：S / CaCO₃ / Fe₂O₃ / Fe / CuSO₄
  { id: 'm_s_1', substanceId: 's', map: MAP_MINE, x: 160, y: 20 },
  { id: 'm_s_2', substanceId: 's', map: MAP_MINE, x: 410, y: 20 },
  { id: 'm_s_3', substanceId: 's', map: MAP_MINE, x: 570, y: 20 },
  { id: 'm_s_4', substanceId: 's', map: MAP_MINE, x: 900, y: 20 },
  { id: 'm_caco3_1', substanceId: 'caco3', map: MAP_MINE, x: 260, y: 0 },
  { id: 'm_caco3_2', substanceId: 'caco3', map: MAP_MINE, x: 660, y: 0 },
  { id: 'm_caco3_3', substanceId: 'caco3', map: MAP_MINE, x: 720, y: 0 },
  { id: 'm_fe2o3_1', substanceId: 'fe2o3', map: MAP_MINE, x: 690, y: 30 },
  { id: 'm_fe2o3_2', substanceId: 'fe2o3', map: MAP_MINE, x: 950, y: 0 },
  { id: 'm_fe_1', substanceId: 'fe', map: MAP_MINE, x: 350, y: 0 },
  { id: 'm_fe_2', substanceId: 'fe', map: MAP_MINE, x: 810, y: 0 },
  { id: 'm_cuso4_1', substanceId: 'cuso4', map: MAP_MINE, x: 580, y: 10 },
];

// 设施定义
export interface FacilityDef {
  id: string;
  map: string;
  x: number;
  radius: number;
}

export const FACILITIES: FacilityDef[] = [
  { id: 'bed', map: MAP_MAIN, x: 2268, radius: 60 },
  { id: 'craft_bench', map: MAP_MAIN, x: 2410, radius: 70 },
  { id: 'campfire', map: MAP_MAIN, x: 2570, radius: 70 },
  { id: 'filter', map: MAP_MAIN, x: 2710, radius: 60 },
  { id: 'electrolyzer', map: MAP_MAIN, x: 2860, radius: 60 },
  { id: 'river', map: MAP_MAIN, x: 2970, radius: 70 },
  { id: 'trader', map: MAP_MAIN, x: 2120, radius: 55 },
  { id: 'signpost', map: MAP_MAIN, x: 2200, radius: 45 },
  { id: 'lakewater', map: MAP_MAIN, x: 512, radius: 460 }, // 盐湖水面（用肥皂水）
];

// 矿洞 CuSO₄ 溶液池（扣血区域）
export const CUSO4_POOL = { x0: 500, x1: 660 };
export const CUSO4_WARN_RADIUS = 150;

// 学院导师站位
export const MENTOR_POSITIONS: Record<string, { x: number; room: string }> = {
  chem: { x: 150, room: '化学实验室' },
  monitor: { x: 395, room: '班主任办公室' },
  assistant: { x: 640, room: '自习室' },
  think: { x: 890, room: '思维工坊' },
};

// 怪物刷新
export const MONSTER_SPAWNS = {
  ghost_mine: [{ x: 400 }, { x: 800 }],          // 矿洞全天 2 只
  ghost_grass_night: [{ x: 1500 }, { x: 1800 }], // 草原夜晚
  slime_camp_night: [{ x: 2150 }, { x: 2950 }, { x: 2600 }], // 夜晚营地外围（取 min~max 只）
};

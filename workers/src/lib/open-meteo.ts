// workers/src/lib/open-meteo.ts
//
// Open-Meteo 取得ラッパー。緊急通知 3 種(熱中症・暴風・大雪)に加え、
// パーソナル通知 5 種(気圧・湿度・AQI・UV・花粉)に必要な変数も取得する。
// spec.md §10(API 設計)/ §12.10.1(WBGT 入力)/ §12.2.3(パーソナル通知)準拠。

export interface OpenMeteoForecast {
  hourly: {
    time: string[];
    temperature_2m: number[];
    relative_humidity_2m: number[];
    shortwave_radiation: number[];
    wind_speed_10m: number[];
    wind_gusts_10m: number[];
    snowfall: number[];          // cm/h
    snow_depth: number[];        // m
    /** パーソナル通知: 気圧急変 / 湿度急上昇 / 強紫外線 用 */
    pressure_msl: number[];      // hPa
    uv_index: number[];          // UV index
    /** 過去 6h ぶんの気圧履歴を含めるため past_hours=6 を併用 */
  };
  daily: {
    time: string[];
    snowfall_sum: number[];      // 日合計 cm
    wind_speed_10m_max: number[];
    wind_gusts_10m_max: number[];
    temperature_2m_max: number[];
    uv_index_max: number[];      // パーソナル通知: 強紫外線
  };
}

/** Open-Meteo Air Quality API (separate host). spec.md §3.1, §12.2.3 */
export interface OpenMeteoAirQuality {
  hourly: {
    time: string[];
    /** 米国 EPA 換算 AQI(0-500)。spec.md §12.2.3 で AQI > 100 を閾値に使用 */
    us_aqi: number[];
    pm2_5: number[];             // µg/m³
    /** 花粉(grains/m³)。日本ではスギ・ヒノキ・ブタクサが主対象(spec.md §12.2.3) */
    alder_pollen: number[];
    birch_pollen: number[];
    grass_pollen: number[];
    mugwort_pollen: number[];
    olive_pollen: number[];
    ragweed_pollen: number[];
  };
}

export async function fetchForecast(
  lat: number,
  lon: number,
  base: string,
): Promise<OpenMeteoForecast> {
  const url = new URL(base);
  url.searchParams.set('latitude', lat.toFixed(4));
  url.searchParams.set('longitude', lon.toFixed(4));
  url.searchParams.set('timezone', 'Asia/Tokyo');
  url.searchParams.set(
    'hourly',
    [
      'temperature_2m',
      'relative_humidity_2m',
      'shortwave_radiation',
      'wind_speed_10m',
      'wind_gusts_10m',
      'snowfall',
      'snow_depth',
      'pressure_msl',
      'uv_index',
    ].join(','),
  );
  url.searchParams.set(
    'daily',
    [
      'snowfall_sum',
      'wind_speed_10m_max',
      'wind_gusts_10m_max',
      'temperature_2m_max',
      'uv_index_max',
    ].join(','),
  );
  url.searchParams.set('forecast_days', '2');
  url.searchParams.set('past_hours', '6');       // 気圧 6h 下降判定(spec.md §12.2.3)
  url.searchParams.set('wind_speed_unit', 'ms'); // m/s で取得(spec.md §12.2.1 風速 15 m/s 判定)

  const res = await fetch(url.toString(), { cf: { cacheTtl: 300 } });
  if (!res.ok) {
    throw new Error(`Open-Meteo HTTP ${res.status}`);
  }
  return (await res.json()) as OpenMeteoForecast;
}

/**
 * Open-Meteo Air Quality (https://air-quality-api.open-meteo.com/v1/air-quality)。
 * AQI と花粉(欧州モデル CAMS)を 1 リクエストで取得する。spec.md §12.2.3。
 * スギ・ヒノキは現状 CAMS で個別公開されていないため、近縁の `alder` / `birch`(初春)/
 * `olive` / `ragweed`(秋)/ `grass` / `mugwort`(夏)で代替し、§9 注釈の通り近似指標として扱う。
 */
export async function fetchAirQuality(
  lat: number,
  lon: number,
  base: string,
): Promise<OpenMeteoAirQuality> {
  const url = new URL(base);
  url.searchParams.set('latitude', lat.toFixed(4));
  url.searchParams.set('longitude', lon.toFixed(4));
  url.searchParams.set('timezone', 'Asia/Tokyo');
  url.searchParams.set(
    'hourly',
    [
      'us_aqi',
      'pm2_5',
      'alder_pollen',
      'birch_pollen',
      'grass_pollen',
      'mugwort_pollen',
      'olive_pollen',
      'ragweed_pollen',
    ].join(','),
  );
  url.searchParams.set('forecast_days', '2');

  const res = await fetch(url.toString(), { cf: { cacheTtl: 600 } });
  if (!res.ok) {
    throw new Error(`Open-Meteo AirQuality HTTP ${res.status}`);
  }
  return (await res.json()) as OpenMeteoAirQuality;
}

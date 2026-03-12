#include "CheezPPG.h"

// PPG定义
#define PPG_PIN A1
#define PPG_SAMPLE_RATE 125

CheezPPG ppg(PPG_PIN, PPG_SAMPLE_RATE);

// GSR定义
#define GSR_PIN A0
const int GSR_SAMPLE_COUNT = 10;          // 滑动平均采样次数
const unsigned long GSR_SAMPLE_INTERVAL = 10; // 采样间隔10ms (100Hz)

int gsrReadings[GSR_SAMPLE_COUNT];        // 存储采样值
int gsrIndex = 0;                          // 当前索引
int gsrSum = 0;                             // 总和
int gsrAverage = 0;                         // 当前平均值
unsigned long lastGSRSampleTime = 0;        // 上次GSR采样时间

void setup() {
  Serial.begin(115200);
  ppg.setWearThreshold(-1); // 不启用佩戴检测
  
  // 初始化GSR数组
  for (int i = 0; i < GSR_SAMPLE_COUNT; i++) {
    gsrReadings[i] = 0;
  }
}

void loop() {
  // 处理PPG采样
  if (ppg.checkSampleInterval()) {
    ppg.ppgProcess();
    
    // 获取PPG数据
    int rawPPG = (int)ppg.getRawPPG();
    int hrv = (int)ppg.getPpgHrv(); // 注意：HRV可能更新较慢，但直接取当前值
    
    // 输出格式: filterPPG, hrv, gsrAverage
    Serial.print(rawPPG);
    Serial.print(",");
    Serial.print(hrv);
    Serial.print(",");
    Serial.println(gsrAverage);
  }
  
  // 处理GSR采样（非阻塞定时）
  unsigned long currentMillis = millis();
  if (currentMillis - lastGSRSampleTime >= GSR_SAMPLE_INTERVAL) {
    lastGSRSampleTime = currentMillis;
    
    // 更新滑动平均
    gsrSum -= gsrReadings[gsrIndex];
    gsrReadings[gsrIndex] = analogRead(GSR_PIN);
    gsrSum += gsrReadings[gsrIndex];
    gsrIndex = (gsrIndex + 1) % GSR_SAMPLE_COUNT;
    gsrAverage = gsrSum / GSR_SAMPLE_COUNT;
    
    // 注意：这里不输出，只更新平均值供PPG输出时使用
  }
}
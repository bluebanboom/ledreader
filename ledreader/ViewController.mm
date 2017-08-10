//
//  ViewController.m
//  ledreader
//

#import <opencv2/opencv.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/imgproc/types_c.h>
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/videoio/cap_ios.h>
#import <time.h>

dispatch_queue_t tx_queue;
dispatch_queue_t rx_queue;

#import "ViewController.h"


@interface ViewController ()<CvVideoCameraDelegate>

@property (nonatomic,strong) CvVideoCamera *videoCamera;

@end

//---------------------------------------------------------------------
static int led = 0;

void delayMS(int ms)
{
    [NSThread sleepForTimeInterval:ms * 1.0 / 1000];
    
    // usleep(ms);
}

void ledDigitalWrite(int pin, int val) {
    
}

// 封装函数，在不同平台上可以重写这个函数来实现点亮LED
void ledOn() {
    // 这里是实验代码，直接以全局静态变量来表示亮灭
    led = 1;
}

// 封装函数，在不同平台上可以重写这个函数来实现关闭LED
void ledOff() {
    // 这里是实验代码，直接以全局静态变量来表示亮灭
    led = 0;
}

// 数据传输开始，先保持灯灭2秒，然后亮2秒表示准备完成
void beginLed() {
    ledOff();
    delayMS(2000);
    ledOn();
    delayMS(2000);
}

// 传输1bit，首先灭60毫秒表示数据即将开始传递
// 传输1，则保持灯亮120毫秒
// 传输0，则保持灯亮60毫秒
void tranBit(int val) {
    ledOff();
    delayMS(60);
    ledOn();
    if (val) {
        NSLog(@"--->1");
        delayMS(120);
    }
    else {
        NSLog(@"--->0");
        delayMS(60);
    }
}

// 数据传输结束保存灯灭500毫秒，这个时间可以加长
void endLed() {
    ledOff();
    delayMS(500);
}

// 对tranBit进一步封装传输1byte
void tranByte(char val) {
    // 先传输高位
    for (int i = 7; i >= 0; i--) {
        tranBit(val >> i & 0x1);
    }
}

// 一个完成的传输过程，实际使用只要调用该函数即可
void sendMsg(char *msg) {
    beginLed();
    while (*msg) {
        tranByte(*msg);
        msg++;
    }
    endLed();
}

//---------------------------------------------------------------------

// 封装函数返回LED的亮灭状态，这里用全局静态变量来表示
int ledStatus() {
    return led;
}

// 等待数据开始，这一部分比较绕
// 其实这里是核心，怎么知道数据开始传输了呢？
// 假如LED只发送一次数据我们比较容易判断开始，但是如果数据是像发广播一样不停发送呢？
// 我们需要找到数据开始的地方，所以，在协议定义的时候数据开始总共有4s就是为了有
// 足够的时间同数据传输时间区分开来
// 这个函数2分钟左右超时，所以单次数据时间不要太多，一分钟最多可以传输32字节左右
// 当然可以调整一下超时，目前只是原型状态
bool waitTranBegin() {
    int count = 0;
    bool result = false;
    struct timespec start;
    struct timespec end;
    
    // 大概2分钟左右超时退出
    while (count < 6000) {
        count++;
        
        // 等待灯亮
        if (ledStatus() == 0) {
            delayMS(10);
            continue;
        }
        
        // 开始检测灯亮时间是否超过1秒
        clock_gettime(CLOCK_REALTIME, &start);
        
        // 每10微秒检测一次
        while (ledStatus() == 1) {
            delayMS(10);
        }
        clock_gettime(CLOCK_REALTIME, &end);
        
        if (end.tv_sec - start.tv_sec >= 1) {
            result = true;
            break;
        }
    }
    return result;
}

// 读取1Bit
// DHT11协议发送的固定位数的数据比较容易处理判断
// 但是我们希望发送不一定长度的数据，所以需要在读取1bit的时候判断一下
// 是不是数据传递结束了。因为我们1bit数据传递时间大概200ms左右
// 所以如果超过200毫秒了还没有读到高电平也就是灯亮，那就表示数据传完了
int readBit(int *end) {
    int count = 0;
    int val = 0;
    
    // 大概200毫秒左右超时退出
    while (count < 20) {
        count++;
        
        // 等待灯亮
        if (ledStatus() == 0) {
            delayMS(10);
            continue;
        }
        
        break;
    }
    
    if (count == 20) {
        // 表示数据已终止
        *end = 1;
    }
    
    delayMS(80);
    val = ledStatus();
    
    // 如果此时传输的是1灯还要亮40毫米左右，需要等待直到灯灭
    if (val) {
        while(ledStatus()) {
            delayMS(10);
        }
    }
    
    return val;
}

// 对readBit的封装也是需要反馈是否传递结束了
char readByte(int *end) {
    char data = 0;
    for (int i = 7; i >= 0; i--) {
        int b = readBit(end);
        if (*end == 1) {
            break;
        }
        
        if (b) {
            data = data | (1 << i);
        }
    }
    
    return data;
}

// 一个完整的的数据读取过程，首先等待数据开始
// 然后依次读取1Byte，最大是1024Byte
// 通过end参数来判断是否数据传递结束了
char *readMsg() {
    if (!waitTranBegin()) {
        return NULL;
    }
    
    char *msg = (char *)malloc(1024);
    int end = 0;
    char c;
    int i = 0;
    
    while (end == 0 && i < 1024) {
        c = readByte(&end);
        msg[i] = c;
        i++;
    }
    
    return msg;
}

//---------------------------------------------------------------------


@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    self.videoCamera = [[CvVideoCamera alloc] initWithParentView:self.imgView];
    self.videoCamera.delegate = self;
    self.videoCamera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionBack;
    self.videoCamera.defaultAVCaptureSessionPreset = AVCaptureSessionPreset640x480;
    self.videoCamera.defaultFPS = 30;
    
    
    tx_queue = dispatch_queue_create("tx_queue", DISPATCH_QUEUE_SERIAL);
    rx_queue = dispatch_queue_create("rx_queue", DISPATCH_QUEUE_SERIAL);
//    [self testFindLed];
//    [self testProtocol];
}

- (void)testFindLed {
    UIImage *image = [UIImage imageNamed:@"ll03"];
    cv::Mat cvImage;
    UIImageToMat(image, cvImage);
    self.imgView.image = image;
    if ([self findLedOn:cvImage]) {
        NSLog(@"Led On");
    }
    else {
        NSLog(@"Led Off");
    }
}

- (void)testProtocol {
    tx_queue = dispatch_queue_create("tx_queue", DISPATCH_QUEUE_SERIAL);
    rx_queue = dispatch_queue_create("rx_queue", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(tx_queue, ^{
        NSLog(@"start send");
        char msg[] = "192.168.1.123";
        sendMsg(msg);
    });
    
    dispatch_async(rx_queue, ^{
        NSLog(@"Wait msg");
        char *msg = readMsg();
        NSLog(@"--->msg = %s", msg);
        NSString *m = [NSString stringWithUTF8String:msg];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.msgLabel.text = m;
        });
        free(msg);
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (IBAction)startAction:(id)sender {
    if (self.videoCamera.running) {
        [self.videoCamera stop];
        [self.startBtn setTitle:@"开始读取" forState:UIControlStateNormal];
    }
    else {
        [self.videoCamera start];
        [self.startBtn setTitle:@"停止读取" forState:UIControlStateNormal];
        
        dispatch_async(rx_queue, ^{
            NSLog(@"Wait msg");
            char *msg = readMsg();
            NSLog(@"--->msg = %s", msg);
            NSString *m = [NSString stringWithUTF8String:msg];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.msgLabel.text = m;
            });
            free(msg);
        });
    }
}

- (void)processImage:(cv::Mat&)image {
    if ([self findLedOn:image]) {
        NSLog(@"--->[1]");
        led = 1;
    }
    else {
        NSLog(@"--->[0]");
        led = 0;
    }
}

- (BOOL)findLedOn:(cv::Mat &)image {
    cv::Mat gray;
    
    // 创建灰度图像
    cv::cvtColor(image, gray, CV_RGB2GRAY);
    
    // 计算直方图
    int size = 64;
    float range[] = {0,255};  //灰度级的范围
    const float *ranges = {range};
    cv::Mat hist;
    calcHist(&gray, 1, 0, cv::Mat(), hist, 1, &size, &ranges, true, false);
    
    // 查找最大亮度，这部分在我们比较理想的状态下应该没有意义，最大值一般是255
    // 由于对OpenCV不是很熟，所以这部分理解不了，解释不清。
    double minVal, maxVal;
    cv::Point minLoc, maxLoc;
    cv::minMaxLoc(gray, &minVal, &maxVal, &minLoc, &maxLoc);
    
    double thresh = maxVal * 0.9;
    cv::Mat threshImg;
    
    // 通过最大值*0.9来二值化图片
    cv::threshold(gray, threshImg, thresh, 255.0, cv::THRESH_BINARY);
    
    // 寻找LED轮廓
    std::vector<std::vector<cv::Point>> contours;
    std::vector<cv::Vec4i> hierarchy;
    cv::findContours(threshImg, contours, hierarchy, CV_RETR_TREE, CV_CHAIN_APPROX_SIMPLE, cv::Point(0, 0));
    
    // 由于可能找到多个轮廓，所以通过轮廓面积大小来判断亮灭
    BOOL ledOn = NO;
    for (int i = 0; i < contours.size(); i++) {
        cv::RotatedRect minRect = minAreaRect(cv::Mat(contours[i]));
        NSLog(@"area->%.3f", minRect.size.area());
        // 通过实验发现亮的LED大概是8000
        if (minRect.size.area() > 3000.0) {
            ledOn = YES;
            break;
        }
    }
    
    return ledOn;
}

@end

# LedReader

通过扫描Led来获取Led传输的信息。

代码依赖OpenCV，下载好代码之后请下载[OpenCV v3.2.0](https://sourceforge.net/projects/opencvlibrary/files/opencv-ios/3.2.0/opencv-3.2.0-ios-framework.zip/download)，将解压后的opencv2.framework放于opencv目录下。



*raspberry/led.c*是树莓派平台上的Led数据发送程序，使用如下命令编译：

	gcc led.c -std=c99 -lwiringPi

 
假设led连接在了GPIO7（WiringPi 11），那么使用如下命令发送Hello：

    ./a.out 11 Hello


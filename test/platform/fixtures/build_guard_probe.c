/* P-22：从源码生成隔离进程，避免复制系统可执行文件的签名及架构约束。 */
#include <stdio.h>
#include <unistd.h>

/* 写入就绪标记后保持存活，供父进程验证构建保护；不访问应用或用户数据。 */
int main(int argc, char **argv) {
    if (argc != 2) {
        return 2;
    }
    FILE *ready = fopen(argv[1], "w");
    if (ready == NULL) {
        return 3;
    }
    if (fputs("ready", ready) == EOF) {
        fclose(ready);
        return 4;
    }
    if (fclose(ready) != 0) {
        return 5;
    }
    sleep(30);
    return 0;
}

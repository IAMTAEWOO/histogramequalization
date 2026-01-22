#include <stdio.h>
#include <stdlib.h>

#define MAX_VAL 255

// 히스토그램 이퀄라이제이션 함수
void histogram_equalization(unsigned char* gray, int totalPixels) {
    int hist[256] = { 0 };
    int cdf[256] = { 0 };
    unsigned char map[256];
    int i;

    // 1. 히스토그램 계산
    for (i = 0; i < totalPixels; i++)
        hist[gray[i]]++;

    // 2. 누적 분포 함수 (CDF)
    cdf[0] = hist[0];
    for (i = 1; i < 256; i++)
        cdf[i] = cdf[i - 1] + hist[i];

    // 3. 최소 CDF 찾기 (0이 아닌 첫 값)
    int cdf_min = 0;
    for (i = 0; i < 256; i++) {
        if (cdf[i] != 0) {
            cdf_min = cdf[i];
            break;
        }
    }

    // 4. 매핑 테이블 생성
    for (i = 0; i < 256; i++) {
        map[i] = (unsigned char)(((cdf[i] - cdf_min) * 255) / (totalPixels - cdf_min));
    }

    // 5. 이퀄라이제이션 적용
    for (i = 0; i < totalPixels; i++)
        gray[i] = map[gray[i]];
}

int main() {
    const char* input_filename = "input.pgm";      // 입력 파일 (이미 grayscale이라고 가정)
    const char* output_filename = "ouput.pgm";

    FILE* fp_in = fopen(input_filename, "rb");
    if (!fp_in) {
        printf("입력 파일 열기 실패: %s\n", input_filename);
        return 1;
    }

    // 헤더 읽기 (P5)
    char format[3];
    int width, height, maxval;
    fscanf(fp_in, "%2s", format);
    if (format[0] != 'P' || format[1] != '5') {
        printf("지원하지 않는 포맷: %s (P5만 지원)\n", format);
        fclose(fp_in);
        return 1;
    }

    // 주석(#) 제거
    int ch;
    while ((ch = fgetc(fp_in)) == '#')
        while (fgetc(fp_in) != '\n');

    ungetc(ch, fp_in);
    fscanf(fp_in, "%d %d", &width, &height);
    fscanf(fp_in, "%d", &maxval);
    fgetc(fp_in); // 개행 문자 소비

    int totalPixels = width * height;
    unsigned char* gray = (unsigned char*)malloc(totalPixels);
    fread(gray, 1, totalPixels, fp_in);
    fclose(fp_in);

    printf("입력 이미지: %s (%dx%d)\n", input_filename, width, height);

    // 히스토그램 이퀄라이제이션 수행
    histogram_equalization(gray, totalPixels);

    // 결과 저장
    FILE* fp_out = fopen(output_filename, "wb");
    fprintf(fp_out, "P5\n%d %d\n%d\n", width, height, MAX_VAL);
    fwrite(gray, 1, totalPixels, fp_out);
    fclose(fp_out);

    printf("히스토그램 이퀄라이제이션 완료 → %s\n", output_filename);

    free(gray);
    return 0;
}

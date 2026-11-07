#include "gcd.h"

/* Dummy: returns 0 for every input. Replace with the binary GCD. */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0u)  // gcd(0,b)=b
        return b;

    if (b == 0u)  // gcd(a,0)=a
        return a;

    unsigned int shift = 0u;

    /* 1.當a,b都是偶數，連續移除共同因數2 */
    while (((a | b) & 1u) == 0u) {
        a >>= 1;
        b >>= 1;
        shift++;
    }

    /* 2.移除2的公因數之後，至少存在一數為奇數，把仍為偶數的數連續除2直到也變成奇數*/
    while ((a & 1u) == 0u) {
        a >>= 1;
    }

    /* 3.兩數都為奇數，將較大數減較小數，直到b=0*/
    do {
        /* 步驟3中的
         * 奇數-奇數=偶數，所以將這個步驟2的判斷是否為偶數放到這個do-while迴圈
         */
        while ((b & 1u) == 0u) {
            b >>= 1;
        }

        /* 比較a,b數的大小，數小的放到左邊 */
        if (a > b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }

        /* 右邊做-> 較大數-較小數 */
        b = b - a;

    } while (b != 0u);

    /* 最後結果是gcd(a,0)，但還要把前面移除的公因數2乘回去 */
    return a << shift;
}

#!/bin/bash
python3 -c "
import math

print('=== explain 原文: log1p(doc[views].value * factor=0.5) ===')
print('   即: log1p(views * 0.5)，注意是 views 先乘 factor，不是 log 之后再乘')
print()

data=[('doc6',0.7444447,2.5886323,6000),
      ('doc1',0.7091,2.4097,5000),
      ('doc4',0.6901,2.192,3000),
      ('doc5',0.3998,1.5991,20000)]

print('假设 log1p 用的是 log10（以 10 为底）:')
print()
print('  doc   views  views*0.5  log10(1+x)  基础分      predicted  实测       差异')
for name,base,final,views in data:
    x=views*0.5
    f=math.log10(1+x)
    pred=base*f
    print('  %-5s %-6s %-10s %-12s %-10s %-10s %-10s %.2e'%(
        name,views,x,round(f,6),base,round(pred,6),final,abs(pred-final)))
print()
print('=== 对比：如果用的是自然对数 ln ===')
for name,base,final,views in data:
    x=views*0.5
    f=math.log(1+x)
    pred=base*f
    print('  %-5s ln(1+%s)=%-12s predicted=%-10s 实测=%-10s 差异=%.4f'%(
        name,x,round(f,6),round(pred,6),final,abs(pred-final)))
print()
print('=== 结论 ===')
"

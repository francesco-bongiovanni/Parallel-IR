; Generate summary sections
; RUN: opt -module-summary %s -o %t1.o
; RUN: opt -module-summary %p/Inputs/thinlto.ll -o %t2.o

; RUN: rm -f %t1.o.4.opt.bc
; RUN: %gold -plugin %llvmshlibdir/LLVMgold.so \
; RUN:    --plugin-opt=thinlto \
; RUN:    --plugin-opt=save-temps \
; RUN:    --plugin-opt=sample-profile=%p/Inputs/afdo.prof \
; RUN:    --plugin-opt=jobs=1 \
; RUN:    -shared %t1.o %t2.o -o %t3
; RUN: opt -S %t1.o.4.opt.bc | FileCheck %s

target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"

; CHECK: ProfileSummary
declare void @g(...)
declare void @h(...)

define void @f() {
entry:
  call void (...) @g()
  call void (...) @h()
  ret void
}

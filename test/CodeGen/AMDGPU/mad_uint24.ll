; RUN: llc < %s -march=r600 -mcpu=redwood | FileCheck %s --check-prefix=EG --check-prefix=FUNC
; RUN: llc < %s -march=r600 -mcpu=cayman | FileCheck %s --check-prefix=EG --check-prefix=FUNC
; RUN: llc < %s -march=amdgcn -mcpu=SI -verify-machineinstrs | FileCheck %s --check-prefix=SI --check-prefix=FUNC
; RUN: llc < %s -march=amdgcn -mcpu=tonga -verify-machineinstrs | FileCheck %s --check-prefix=VI --check-prefix=FUNC
; RUN: llc < %s -march=amdgcn -mcpu=fiji -verify-machineinstrs | FileCheck %s --check-prefix=VI --check-prefix=FUNC

declare i32 @llvm.r600.read.tidig.x() nounwind readnone

; FUNC-LABEL: {{^}}u32_mad24:
; EG: MULADD_UINT24
; SI: v_mad_u32_u24
; VI: v_mad_u32_u24

define void @u32_mad24(i32 addrspace(1)* %out, i32 %a, i32 %b, i32 %c) {
entry:
  %0 = shl i32 %a, 8
  %a_24 = lshr i32 %0, 8
  %1 = shl i32 %b, 8
  %b_24 = lshr i32 %1, 8
  %2 = mul i32 %a_24, %b_24
  %3 = add i32 %2, %c
  store i32 %3, i32 addrspace(1)* %out
  ret void
}

; FUNC-LABEL: {{^}}i16_mad24:
; The order of A and B does not matter.
; EG: MULADD_UINT24 {{[* ]*}}T{{[0-9]}}.[[MAD_CHAN:[XYZW]]]
; The result must be sign-extended
; EG: BFE_INT {{[* ]*}}T{{[0-9]\.[XYZW]}}, PV.[[MAD_CHAN]], 0.0, literal.x
; EG: 16
; FIXME: Should be using scalar instructions here.
; GCN: v_mad_u32_u24 [[MAD:v[0-9]]], {{[sv][0-9], [sv][0-9]}}
; GCN: v_bfe_i32 v{{[0-9]}}, [[MAD]], 0, 16
define void @i16_mad24(i32 addrspace(1)* %out, i16 %a, i16 %b, i16 %c) {
entry:
  %0 = mul i16 %a, %b
  %1 = add i16 %0, %c
  %2 = sext i16 %1 to i32
  store i32 %2, i32 addrspace(1)* %out
  ret void
}

; FIXME: Need to handle non-uniform case for function below (load without gep).
; FUNC-LABEL: {{^}}i8_mad24:
; EG: MULADD_UINT24 {{[* ]*}}T{{[0-9]}}.[[MAD_CHAN:[XYZW]]]
; The result must be sign-extended
; EG: BFE_INT {{[* ]*}}T{{[0-9]\.[XYZW]}}, PV.[[MAD_CHAN]], 0.0, literal.x
; EG: 8
; GCN: v_mad_u32_u24 [[MUL:v[0-9]]], {{[sv][0-9], [sv][0-9]}}
; GCN: v_bfe_i32 v{{[0-9]}}, [[MUL]], 0, 8
define void @i8_mad24(i32 addrspace(1)* %out, i8 %a, i8 %b, i8 %c) {
entry:
  %0 = mul i8 %a, %b
  %1 = add i8 %0, %c
  %2 = sext i8 %1 to i32
  store i32 %2, i32 addrspace(1)* %out
  ret void
}

; This tests for a bug where the mad_u24 pattern matcher would call
; SimplifyDemandedBits on the first operand of the mul instruction
; assuming that the pattern would be matched to a 24-bit mad.  This
; led to some instructions being incorrectly erased when the entire
; 24-bit mad pattern wasn't being matched.

; Check that the select instruction is not deleted.
; FUNC-LABEL: {{^}}i24_i32_i32_mad:
; EG: CNDE_INT
; SI: v_cndmask
define void @i24_i32_i32_mad(i32 addrspace(1)* %out, i32 %a, i32 %b, i32 %c, i32 %d) {
entry:
  %0 = ashr i32 %a, 8
  %1 = icmp ne i32 %c, 0
  %2 = select i1 %1, i32 %0, i32 34
  %3 = mul i32 %2, %c
  %4 = add i32 %3, %d
  store i32 %4, i32 addrspace(1)* %out
  ret void
}

; FUNC-LABEL: {{^}}extra_and:
; SI-NOT: v_and
; SI: v_mad_u32_u24
; SI: v_mad_u32_u24
define amdgpu_kernel void @extra_and(i32 addrspace(1)* %arg, i32 %arg2, i32 %arg3) {
bb:
  br label %bb4

bb4:                                              ; preds = %bb4, %bb
  %tmp = phi i32 [ 0, %bb ], [ %tmp13, %bb4 ]
  %tmp5 = phi i32 [ 0, %bb ], [ %tmp13, %bb4 ]
  %tmp6 = phi i32 [ 0, %bb ], [ %tmp15, %bb4 ]
  %tmp7 = phi i32 [ 0, %bb ], [ %tmp15, %bb4 ]
  %tmp8 = and i32 %tmp7, 16777215
  %tmp9 = and i32 %tmp6, 16777215
  %tmp10 = and i32 %tmp5, 16777215
  %tmp11 = and i32 %tmp, 16777215
  %tmp12 = mul i32 %tmp8, %tmp11
  %tmp13 = add i32 %arg2, %tmp12
  %tmp14 = mul i32 %tmp9, %tmp11
  %tmp15 = add i32 %arg3, %tmp14
  %tmp16 = add nuw nsw i32 %tmp13, %tmp15
  %tmp17 = icmp eq i32 %tmp16, 8
  br i1 %tmp17, label %bb18, label %bb4

bb18:                                             ; preds = %bb4
  store i32 %tmp16, i32 addrspace(1)* %arg
  ret void
}

; FUNC-LABEL: {{^}}dont_remove_shift
; SI: v_lshr
; SI: v_mad_u32_u24
; SI: v_mad_u32_u24
define amdgpu_kernel void @dont_remove_shift(i32 addrspace(1)* %arg, i32 %arg2, i32 %arg3) {
bb:
  br label %bb4

bb4:                                              ; preds = %bb4, %bb
  %tmp = phi i32 [ 0, %bb ], [ %tmp13, %bb4 ]
  %tmp5 = phi i32 [ 0, %bb ], [ %tmp13, %bb4 ]
  %tmp6 = phi i32 [ 0, %bb ], [ %tmp15, %bb4 ]
  %tmp7 = phi i32 [ 0, %bb ], [ %tmp15, %bb4 ]
  %tmp8 = lshr i32 %tmp7, 8
  %tmp9 = lshr i32 %tmp6, 8
  %tmp10 = lshr i32 %tmp5, 8
  %tmp11 = lshr i32 %tmp, 8
  %tmp12 = mul i32 %tmp8, %tmp11
  %tmp13 = add i32 %arg2, %tmp12
  %tmp14 = mul i32 %tmp9, %tmp11
  %tmp15 = add i32 %arg3, %tmp14
  %tmp16 = add nuw nsw i32 %tmp13, %tmp15
  %tmp17 = icmp eq i32 %tmp16, 8
  br i1 %tmp17, label %bb18, label %bb4

bb18:                                             ; preds = %bb4
  store i32 %tmp16, i32 addrspace(1)* %arg
  ret void
}

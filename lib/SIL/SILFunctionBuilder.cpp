//===--- SILFunctionBuilder.cpp -------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "swift/SIL/SILFunctionBuilder.h"
#include "swift/AST/Decl.h"
using namespace swift;

SILFunction *SILFunctionBuilder::getOrCreateFunction(
    SILLocation loc, StringRef name, SILLinkage linkage,
    CanSILFunctionType type, IsBare_t isBareSILFunction,
    IsTransparent_t isTransparent, IsSerialized_t isSerialized,
    IsDynamicallyReplaceable_t isDynamic, ProfileCounter entryCount,
    IsThunk_t isThunk, SubclassScope subclassScope) {
  assert(!type->isNoEscape() && "Function decls always have escaping types.");
  if (auto fn = mod.lookUpFunction(name)) {
    assert(fn->getLoweredFunctionType() == type);
    assert(stripExternalFromLinkage(fn->getLinkage()) ==
           stripExternalFromLinkage(linkage));
    return fn;
  }

  auto fn = SILFunction::create(mod, linkage, name, type, nullptr, loc,
                                isBareSILFunction, isTransparent, isSerialized,
                                entryCount, isDynamic, isThunk, subclassScope);
  fn->setDebugScope(new (mod) SILDebugScope(loc, fn));
  return fn;
}

void SILFunctionBuilder::addFunctionAttributes(SILFunction *F,
                                               DeclAttributes &Attrs,
                                               SILModule &M,
                                               SILDeclRef constant) {

  for (auto *A : Attrs.getAttributes<SemanticsAttr>())
    F->addSemanticsAttr(cast<SemanticsAttr>(A)->Value);

  // Propagate @_specialize.
  for (auto *A : Attrs.getAttributes<SpecializeAttr>()) {
    auto *SA = cast<SpecializeAttr>(A);
    auto kind =
        SA->getSpecializationKind() == SpecializeAttr::SpecializationKind::Full
            ? SILSpecializeAttr::SpecializationKind::Full
            : SILSpecializeAttr::SpecializationKind::Partial;
    F->addSpecializeAttr(SILSpecializeAttr::create(M, SA->getRequirements(),
                                                   SA->isExported(), kind));
  }

  if (auto *OA = Attrs.getAttribute<OptimizeAttr>()) {
    F->setOptimizationMode(OA->getMode());
  }

  // @_silgen_name and @_cdecl functions may be called from C code somewhere.
  if (Attrs.hasAttribute<SILGenNameAttr>() || Attrs.hasAttribute<CDeclAttr>())
    F->setHasCReferences(true);

  // Propagate @_dynamicReplacement(for:).
  if (constant.isNull())
    return;
  auto *decl = constant.getDecl();

  // SWIFT_ENABLE_TENSORFLOW
  // Propagate @differentiable attributes.
  // Don't propagate @differentiable to:
  // - Non-getter accessors (setters, modifiers, etc).
  // - Default argument generator functions.
  // - Thunks. Those are currently handled in SILGenThunk.cpp.
  if ((!isa<AccessorDecl>(decl) || cast<AccessorDecl>(decl)->isGetter()) &&
      constant.kind != SILDeclRef::Kind::DefaultArgGenerator &&
      !constant.autoDiffAssociatedFunctionIdentifier &&
      !constant.isStoredPropertyInitializer() &&
      !constant.isThunk()) {
    for (auto *A : Attrs.getAttributes<DifferentiableAttr>()) {
      std::string jvpName, vjpName;
      // Get JVP/VJP names.
      if (auto *jvpFn = A->getJVPFunction())
        jvpName = SILDeclRef(jvpFn).mangle();
      if (auto *vjpFn = A->getVJPFunction())
        vjpName = SILDeclRef(vjpFn).mangle();
      // Get lowered argument indices.
      auto paramIndices = A->getParameterIndices();
      auto loweredParamIndices = paramIndices->getLowered(
          decl->getInterfaceType()->castTo<AnyFunctionType>());
      SILAutoDiffIndices indices(/*source*/ 0, loweredParamIndices);
      auto silDiffAttr = SILDifferentiableAttr::create(
          M, indices, A->getRequirements(), M.allocateCopy(jvpName),
          M.allocateCopy(vjpName));
      F->addDifferentiableAttr(silDiffAttr);
    }
  }

  // Only emit replacements for the objc entry point of objc methods.
  if (decl->isObjC() &&
      F->getLoweredFunctionType()->getExtInfo().getRepresentation() !=
          SILFunctionTypeRepresentation::ObjCMethod)
    return;

  auto *replacedFuncAttr = Attrs.getAttribute<DynamicReplacementAttr>();
  if (!replacedFuncAttr)
    return;

  auto *replacedDecl = replacedFuncAttr->getReplacedFunction();
  assert(replacedDecl);

  if (decl->isObjC()) {
    F->setObjCReplacement(replacedDecl);
    return;
  }

  if (constant.isInitializerOrDestroyer())
    return;

  SILDeclRef declRef(replacedDecl, constant.kind, false);
  auto *replacedFunc =
      getOrCreateFunction(replacedDecl, declRef, NotForDefinition);
  assert(replacedFunc->getLoweredFunctionType() == F->getLoweredFunctionType());
  F->setDynamicallyReplacedFunction(replacedFunc);

}

SILFunction *
SILFunctionBuilder::getOrCreateFunction(SILLocation loc, SILDeclRef constant,
                                        ForDefinition_t forDefinition,
                                        ProfileCounter entryCount) {
  auto nameTmp = constant.mangle();
  auto constantType = mod.Types.getConstantFunctionType(constant);
  SILLinkage linkage = constant.getLinkage(forDefinition);

  if (auto fn = mod.lookUpFunction(nameTmp)) {
    assert(fn->getLoweredFunctionType() == constantType);
    assert(fn->getLinkage() == linkage ||
           (forDefinition == ForDefinition_t::NotForDefinition &&
            fn->getLinkage() ==
                constant.getLinkage(ForDefinition_t::ForDefinition)));
    if (forDefinition) {
      // In all the cases where getConstantLinkage returns something
      // different for ForDefinition, it returns an available-externally
      // linkage.
      if (isAvailableExternally(fn->getLinkage())) {
        fn->setLinkage(constant.getLinkage(ForDefinition));
      }
    }
    return fn;
  }

  IsTransparent_t IsTrans =
      constant.isTransparent() ? IsTransparent : IsNotTransparent;
  IsSerialized_t IsSer = constant.isSerialized();

  EffectsKind EK = constant.hasEffectsAttribute()
                       ? constant.getEffectsAttribute()
                       : EffectsKind::Unspecified;

  Inline_t inlineStrategy = InlineDefault;
  if (constant.isNoinline())
    inlineStrategy = NoInline;
  else if (constant.isAlwaysInline())
    inlineStrategy = AlwaysInline;

  StringRef name = mod.allocateCopy(nameTmp);
  IsDynamicallyReplaceable_t IsDyn = IsNotDynamic;
  if (constant.isDynamicallyReplaceable()) {
    IsDyn = IsDynamic;
    IsTrans = IsNotTransparent;
  }

  auto *F = SILFunction::create(mod, linkage, name, constantType, nullptr, None,
                                IsNotBare, IsTrans, IsSer, entryCount, IsDyn,
                                IsNotThunk, constant.getSubclassScope(),
                                inlineStrategy, EK);
  F->setDebugScope(new (mod) SILDebugScope(loc, F));

  F->setGlobalInit(constant.isGlobal());
  if (constant.hasDecl()) {
    auto decl = constant.getDecl();

    if (constant.isForeign && decl->hasClangNode())
      F->setClangNodeOwner(decl);

    if (decl->isWeakImported(/*fromModule=*/nullptr))
      F->setWeakLinked();

    if (auto *accessor = dyn_cast<AccessorDecl>(decl)) {
      auto *storage = accessor->getStorage();
      // SWIFT_ENABLE_TENSORFLOW
      addFunctionAttributes(F, storage->getAttrs(), mod, constant);
    }
    // SWIFT_ENABLE_TENSORFLOW
    addFunctionAttributes(F, decl->getAttrs(), mod, constant);
  }

  return F;
}

SILFunction *SILFunctionBuilder::getOrCreateSharedFunction(
    SILLocation loc, StringRef name, CanSILFunctionType type,
    IsBare_t isBareSILFunction, IsTransparent_t isTransparent,
    IsSerialized_t isSerialized, ProfileCounter entryCount, IsThunk_t isThunk,
    IsDynamicallyReplaceable_t isDynamic) {
  return getOrCreateFunction(loc, name, SILLinkage::Shared, type,
                             isBareSILFunction, isTransparent, isSerialized,
                             isDynamic, entryCount, isThunk,
                             SubclassScope::NotApplicable);
}

SILFunction *SILFunctionBuilder::createFunction(
    SILLinkage linkage, StringRef name, CanSILFunctionType loweredType,
    GenericEnvironment *genericEnv, Optional<SILLocation> loc,
    IsBare_t isBareSILFunction, IsTransparent_t isTrans,
    IsSerialized_t isSerialized, IsDynamicallyReplaceable_t isDynamic,
    ProfileCounter entryCount, IsThunk_t isThunk, SubclassScope subclassScope,
    Inline_t inlineStrategy, EffectsKind EK, SILFunction *InsertBefore,
    const SILDebugScope *DebugScope) {
  return SILFunction::create(mod, linkage, name, loweredType, genericEnv, loc,
                             isBareSILFunction, isTrans, isSerialized,
                             entryCount, isDynamic, isThunk, subclassScope,
                             inlineStrategy, EK, InsertBefore, DebugScope);
}

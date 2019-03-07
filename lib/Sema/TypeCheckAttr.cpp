//===--- TypeCheckAttr.cpp - Type Checking for Attributes -----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// This file implements semantic analysis for attributes.
//
//===----------------------------------------------------------------------===//

#include "TypeChecker.h"
#include "MiscDiagnostics.h"
#include "TypeCheckType.h"
#include "swift/AST/GenericSignatureBuilder.h"
#include "swift/AST/ASTVisitor.h"
#include "swift/AST/ClangModuleLoader.h"
#include "swift/AST/GenericEnvironment.h"
#include "swift/AST/NameLookup.h"
#include "swift/AST/ParameterList.h"
// SWIFT_ENABLE_TENSORFLOW
#include "swift/AST/TensorFlow.h"
#include "swift/AST/TypeCheckRequests.h"
#include "swift/AST/Types.h"
#include "swift/Parse/Lexer.h"
#include "llvm/Support/Debug.h"

using namespace swift;

namespace {
  /// This emits a diagnostic with a fixit to remove the attribute.
  template<typename ...ArgTypes>
  void diagnoseAndRemoveAttr(TypeChecker &TC, Decl *D, DeclAttribute *attr,
                             ArgTypes &&...Args) {
    assert(!D->hasClangNode() && "Clang imported propagated a bogus attribute");
    if (!D->hasClangNode()) {
      SourceLoc loc = attr->getLocation();
      assert(loc.isValid() && "Diagnosing attribute with invalid location");
      if (loc.isInvalid()) {
        loc = D->getLoc();
      }
      if (loc.isValid()) {
        TC.diagnose(loc, std::forward<ArgTypes>(Args)...)
          .fixItRemove(attr->getRangeWithAt());
      }
    }

    attr->setInvalid();
  }

/// This visits each attribute on a decl early, before the majority of type
/// checking has been performed for the decl.  The visitor should return true if
/// the attribute is invalid and should be marked as such.
class AttributeEarlyChecker : public AttributeVisitor<AttributeEarlyChecker> {
  TypeChecker &TC;
  Decl *D;

public:
  AttributeEarlyChecker(TypeChecker &TC, Decl *D) : TC(TC), D(D) {}

  /// This emits a diagnostic with a fixit to remove the attribute.
  template<typename ...ArgTypes>
  void diagnoseAndRemoveAttr(DeclAttribute *attr, ArgTypes &&...Args) {
    ::diagnoseAndRemoveAttr(TC, D, attr, std::forward<ArgTypes>(Args)...);
  }

  /// Deleting this ensures that all attributes are covered by the visitor
  /// below.
  bool visitDeclAttribute(DeclAttribute *A) = delete;

#define IGNORED_ATTR(X) void visit##X##Attr(X##Attr *) {}
  IGNORED_ATTR(Available)
  IGNORED_ATTR(HasInitialValue)
  IGNORED_ATTR(CDecl)
  IGNORED_ATTR(ClangImporterSynthesizedType)
  IGNORED_ATTR(Convenience)
  IGNORED_ATTR(DiscardableResult)
  IGNORED_ATTR(DynamicCallable)
  IGNORED_ATTR(DynamicMemberLookup)
  IGNORED_ATTR(Effects)
  IGNORED_ATTR(Exported)
  IGNORED_ATTR(FixedLayout)
  IGNORED_ATTR(ForbidSerializingReference)
  IGNORED_ATTR(Frozen)
  IGNORED_ATTR(Implements)
  IGNORED_ATTR(ImplicitlyUnwrappedOptional)
  IGNORED_ATTR(Infix)
  IGNORED_ATTR(Inlinable)
  IGNORED_ATTR(Inline)
  IGNORED_ATTR(NonObjC)
  IGNORED_ATTR(NSApplicationMain)
  IGNORED_ATTR(NSCopying)
  IGNORED_ATTR(ObjC)
  IGNORED_ATTR(ObjCBridged)
  IGNORED_ATTR(ObjCNonLazyRealization)
  IGNORED_ATTR(ObjCRuntimeName)
  IGNORED_ATTR(Optimize)
  IGNORED_ATTR(Optional)
  IGNORED_ATTR(Postfix)
  IGNORED_ATTR(Prefix)
  IGNORED_ATTR(RawDocComment)
  IGNORED_ATTR(Required)
  IGNORED_ATTR(RequiresStoredPropertyInits)
  IGNORED_ATTR(RestatedObjCConformance)
  IGNORED_ATTR(Rethrows)
  IGNORED_ATTR(Semantics)
  IGNORED_ATTR(ShowInInterface)
  IGNORED_ATTR(SILGenName)
  IGNORED_ATTR(Specialize)
  IGNORED_ATTR(StaticInitializeObjCMetadata)
  IGNORED_ATTR(SwiftNativeObjCRuntimeBase)
  IGNORED_ATTR(SynthesizedProtocol)
  IGNORED_ATTR(Testable)
  IGNORED_ATTR(UIApplicationMain)
  IGNORED_ATTR(UnsafeNoObjCTaggedPointer)
  IGNORED_ATTR(UsableFromInline)
  IGNORED_ATTR(WeakLinked)
  IGNORED_ATTR(DynamicReplacement)
  IGNORED_ATTR(PrivateImport)
  // SWIFT_ENABLE_TENSORFLOW
  IGNORED_ATTR(Differentiable)
  IGNORED_ATTR(Differentiating)
  IGNORED_ATTR(CompilerEvaluable)
  IGNORED_ATTR(TensorFlowGraph)
  IGNORED_ATTR(FieldwiseDifferentiable)
  IGNORED_ATTR(NoDerivative)
#undef IGNORED_ATTR

  // @noreturn has been replaced with a 'Never' return type.
  void visitNoReturnAttr(NoReturnAttr *attr) {
    if (auto FD = dyn_cast<FuncDecl>(D)) {
      auto &SM = TC.Context.SourceMgr;

      auto diag = TC.diagnose(attr->getLocation(),
                              diag::noreturn_not_supported);
      auto range = attr->getRangeWithAt();
      if (range.isValid())
        range.End = range.End.getAdvancedLoc(1);
      diag.fixItRemove(range);

      auto *last = FD->getParameters();

      // If the declaration already has a result type, we're going
      // to change it to 'Never'.
      bool hadResultType = false;
      bool isEndOfLine = false;
      SourceLoc resultLoc;
      if (FD->getBodyResultTypeLoc().hasLocation()) {
        const auto &typeLoc = FD->getBodyResultTypeLoc();
        hadResultType = true;
        resultLoc = typeLoc.getSourceRange().Start;

      // If the function 'throws', insert the result type after the
      // 'throws'.
      } else {
        if (FD->getThrowsLoc().isValid()) {
          resultLoc = FD->getThrowsLoc();

        // Otherwise, insert the result type after the final parameter
        // list.
        } else if (last->getRParenLoc().isValid()) {
          resultLoc = last->getRParenLoc();
        }

        if (Lexer::getLocForEndOfToken(SM, resultLoc).getAdvancedLoc(1) ==
            Lexer::getLocForEndOfLine(SM, resultLoc))
          isEndOfLine = true;

        resultLoc = Lexer::getLocForEndOfToken(SM, resultLoc);
      }

      if (hadResultType) {
        diag.fixItReplace(resultLoc, "Never");
      } else {
        std::string fix = " -> Never";

        if (!isEndOfLine)
          fix = fix + " ";

        diag.fixItInsert(resultLoc, fix);
      }

      auto neverType = TC.Context.getNeverType();
      if (neverType)
        FD->getBodyResultTypeLoc() = TypeLoc::withoutLoc(neverType);
    }
  }

  void visitAlignmentAttr(AlignmentAttr *attr) {
    // Alignment must be a power of two.
    auto value = attr->getValue();
    if (value == 0 || (value & (value - 1)) != 0)
      TC.diagnose(attr->getLocation(), diag::alignment_not_power_of_two);
  }

  void visitBorrowedAttr(BorrowedAttr *attr) {
    // These criteria are the same preconditions laid out by
    // AbstractStorageDecl::requiresOpaqueModifyCoroutine().

    assert(!D->hasClangNode() && "@_borrowed on imported declaration?");

    if (D->getAttrs().hasAttribute<DynamicAttr>()) {
      TC.diagnose(attr->getLocation(), diag::borrowed_with_objc_dynamic,
                  D->getDescriptiveKind())
        .fixItRemove(attr->getRange());
      D->getAttrs().removeAttribute(attr);
      return;
    }

    auto dc = D->getDeclContext();
    auto protoDecl = dyn_cast<ProtocolDecl>(dc);
    if (protoDecl && protoDecl->isObjC()) {
      TC.diagnose(attr->getLocation(),
                  diag::borrowed_on_objc_protocol_requirement,
                  D->getDescriptiveKind())
        .fixItRemove(attr->getRange());
      D->getAttrs().removeAttribute(attr);
      return;
    }
  }

  void visitTransparentAttr(TransparentAttr *attr);
  void visitMutationAttr(DeclAttribute *attr);
  void visitMutatingAttr(MutatingAttr *attr) { visitMutationAttr(attr); }
  void visitNonMutatingAttr(NonMutatingAttr *attr) { visitMutationAttr(attr); }
  void visitConsumingAttr(ConsumingAttr *attr) { visitMutationAttr(attr); }
  void visitDynamicAttr(DynamicAttr *attr);

  void visitReferenceOwnershipAttr(ReferenceOwnershipAttr *attr) {
    TC.checkReferenceOwnershipAttr(cast<VarDecl>(D), attr);
  }

  void visitFinalAttr(FinalAttr *attr) {
    // Reject combining 'final' with 'open'.
    if (auto accessAttr = D->getAttrs().getAttribute<AccessControlAttr>()) {
      if (accessAttr->getAccess() == AccessLevel::Open) {
        TC.diagnose(attr->getLocation(), diag::open_decl_cannot_be_final,
                    D->getDescriptiveKind());
        return;
      }
    }

    if (isa<ClassDecl>(D))
      return;

    // 'final' only makes sense in the context of a class declaration.
    // Reject it on global functions, protocols, structs, enums, etc.
    if (!D->getDeclContext()->getSelfClassDecl()) {
      TC.diagnose(attr->getLocation(), diag::member_cannot_be_final)
        .fixItRemove(attr->getRange());

      // Remove the attribute so child declarations are not flagged as final
      // and duplicate the error message.
      D->getAttrs().removeAttribute(attr);
      return;
    }
  }

  void visitIndirectAttr(IndirectAttr *attr) {
    if (auto caseDecl = dyn_cast<EnumElementDecl>(D)) {
      // An indirect case should have a payload.
      if (!caseDecl->hasAssociatedValues())
        TC.diagnose(attr->getLocation(),
                    diag::indirect_case_without_payload, caseDecl->getName());
      // If the enum is already indirect, its cases don't need to be.
      else if (caseDecl->getParentEnum()->getAttrs()
                 .hasAttribute<IndirectAttr>())
        TC.diagnose(attr->getLocation(),
                    diag::indirect_case_in_indirect_enum);
    }
  }

  void visitWarnUnqualifiedAccessAttr(WarnUnqualifiedAccessAttr *attr) {
    if (!D->getDeclContext()->isTypeContext()) {
      diagnoseAndRemoveAttr(attr, diag::attr_methods_only, attr);
    }
  }

  void visitIBActionAttr(IBActionAttr *attr);
  void visitLazyAttr(LazyAttr *attr);
  void visitIBDesignableAttr(IBDesignableAttr *attr);
  void visitIBInspectableAttr(IBInspectableAttr *attr);
  void visitGKInspectableAttr(GKInspectableAttr *attr);
  void visitIBOutletAttr(IBOutletAttr *attr);
  void visitLLDBDebuggerFunctionAttr(LLDBDebuggerFunctionAttr *attr);
  void visitNSManagedAttr(NSManagedAttr *attr);
  void visitOverrideAttr(OverrideAttr *attr);
  void visitNonOverrideAttr(NonOverrideAttr *attr);
  void visitAccessControlAttr(AccessControlAttr *attr);
  void visitSetterAccessAttr(SetterAccessAttr *attr);
  bool visitAbstractAccessControlAttr(AbstractAccessControlAttr *attr);
  void visitHasStorageAttr(HasStorageAttr *attr);
  void visitObjCMembersAttr(ObjCMembersAttr *attr);
};
} // end anonymous namespace

void AttributeEarlyChecker::visitTransparentAttr(TransparentAttr *attr) {
  DeclContext *Ctx = D->getDeclContext();
  // Protocol declarations cannot be transparent.
  if (isa<ProtocolDecl>(Ctx))
    diagnoseAndRemoveAttr(attr, diag::transparent_in_protocols_not_supported);
  // Class declarations cannot be transparent.
  if (isa<ClassDecl>(Ctx)) {
    
    // @transparent is always ok on implicitly generated accessors: they can
    // be dispatched (even in classes) when the references are within the
    // class themself.
    if (!(isa<AccessorDecl>(D) && D->isImplicit()))
      diagnoseAndRemoveAttr(attr, diag::transparent_in_classes_not_supported);
  }
  
  if (auto *VD = dyn_cast<VarDecl>(D)) {
    // Stored properties and variables can't be transparent.
    if (VD->hasStorage())
      diagnoseAndRemoveAttr(attr, diag::attribute_invalid_on_stored_property,
                            attr);
  }
}

void AttributeEarlyChecker::visitMutationAttr(DeclAttribute *attr) {
  FuncDecl *FD = cast<FuncDecl>(D);

  SelfAccessKind attrModifier;
  switch (attr->getKind()) {
  case DeclAttrKind::DAK_Consuming:
    attrModifier = SelfAccessKind::__Consuming;
    break;
  case DeclAttrKind::DAK_Mutating:
    attrModifier = SelfAccessKind::Mutating;
    break;
  case DeclAttrKind::DAK_NonMutating:
    attrModifier = SelfAccessKind::NonMutating;
    break;
  default:
    llvm_unreachable("unhandled attribute kind");
  }

  // mutation attributes may only appear in type context.
  if (auto contextTy = FD->getDeclContext()->getDeclaredInterfaceType()) {
    // 'mutating' and 'nonmutating' are not valid on types
    // with reference semantics.
    if (contextTy->hasReferenceSemantics()) {
      if (attrModifier != SelfAccessKind::__Consuming)
        diagnoseAndRemoveAttr(attr, diag::mutating_invalid_classes,
                              unsigned(attrModifier));
    }
  } else {
    diagnoseAndRemoveAttr(attr, diag::mutating_invalid_global_scope,
                          unsigned(attrModifier));
  }

  // Verify we don't have more than one of mutating, nonmutating,
  // and __consuming.
  if ((FD->getAttrs().hasAttribute<MutatingAttr>() +
          FD->getAttrs().hasAttribute<NonMutatingAttr>() +
          FD->getAttrs().hasAttribute<ConsumingAttr>()) > 1) {
    if (auto *NMA = FD->getAttrs().getAttribute<NonMutatingAttr>()) {
      if (attrModifier != SelfAccessKind::NonMutating) {
        diagnoseAndRemoveAttr(NMA, diag::functions_mutating_and_not,
                              unsigned(SelfAccessKind::NonMutating),
                              unsigned(attrModifier));
      }
    }

    if (auto *MUA = FD->getAttrs().getAttribute<MutatingAttr>()) {
      if (attrModifier != SelfAccessKind::Mutating) {
        diagnoseAndRemoveAttr(MUA, diag::functions_mutating_and_not,
                                unsigned(SelfAccessKind::Mutating),
                                unsigned(attrModifier));
      }
    }

    if (auto *CSA = FD->getAttrs().getAttribute<ConsumingAttr>()) {
      if (attrModifier != SelfAccessKind::__Consuming) {
        diagnoseAndRemoveAttr(CSA, diag::functions_mutating_and_not,
                              unsigned(SelfAccessKind::__Consuming),
                              unsigned(attrModifier));
      }
    }
  }
  
  // Verify that we don't have a static function.
  if (FD->isStatic())
    diagnoseAndRemoveAttr(attr, diag::static_functions_not_mutating);
}

void AttributeEarlyChecker::visitDynamicAttr(DynamicAttr *attr) {
  // Members cannot be both dynamic and final.
  if (D->getAttrs().hasAttribute<FinalAttr>())
    diagnoseAndRemoveAttr(attr, diag::dynamic_with_final);

  // Members cannot be both dynamic and @nonobjc.
  if (D->getAttrs().hasAttribute<NonObjCAttr>())
    diagnoseAndRemoveAttr(attr, diag::dynamic_with_nonobjc);

  // Members cannot be both dynamic and @_transparent.
  if (D->getASTContext().LangOpts.isSwiftVersionAtLeast(5) &&
      D->getAttrs().hasAttribute<TransparentAttr>())
    diagnoseAndRemoveAttr(attr, diag::dynamic_with_transparent);
}


void AttributeEarlyChecker::visitIBActionAttr(IBActionAttr *attr) {
  // Only instance methods returning () can be IBActions.
  const FuncDecl *FD = cast<FuncDecl>(D);
  if (!FD->isPotentialIBActionTarget())
    diagnoseAndRemoveAttr(attr, diag::invalid_ibaction_decl);
}

void AttributeEarlyChecker::visitIBDesignableAttr(IBDesignableAttr *attr) {
  if (auto *ED = dyn_cast<ExtensionDecl>(D)) {
    if (auto nominalDecl = ED->getExtendedNominal()) {
      if (!isa<ClassDecl>(nominalDecl))
        diagnoseAndRemoveAttr(attr, diag::invalid_ibdesignable_extension);
    }
  }
}

void AttributeEarlyChecker::visitIBInspectableAttr(IBInspectableAttr *attr) {
  // Only instance properties can be 'IBInspectable'.
  auto *VD = cast<VarDecl>(D);
  if (!VD->getDeclContext()->getSelfClassDecl() || VD->isStatic())
    diagnoseAndRemoveAttr(attr, diag::invalid_ibinspectable,
                                 attr->getAttrName());
}

void AttributeEarlyChecker::visitGKInspectableAttr(GKInspectableAttr *attr) {
  // Only instance properties can be 'GKInspectable'.
  auto *VD = cast<VarDecl>(D);
  if (!VD->getDeclContext()->getSelfClassDecl() || VD->isStatic())
    diagnoseAndRemoveAttr(attr, diag::invalid_ibinspectable,
                                 attr->getAttrName());
}

void AttributeEarlyChecker::visitHasStorageAttr(HasStorageAttr *attr) {
  auto *VD = cast<VarDecl>(D);
  if (VD->getDeclContext()->getSelfClassDecl())
    return;
  auto nominalDecl = VD->getDeclContext()->getSelfNominalTypeDecl();
  if (nominalDecl && isa<StructDecl>(nominalDecl))
    return;
  diagnoseAndRemoveAttr(attr, diag::invalid_decl_attribute_simple);
}

static Optional<Diag<bool,Type>>
isAcceptableOutletType(Type type, bool &isArray, TypeChecker &TC) {
  if (type->isObjCExistentialType() || type->isAny())
    return None; // @objc existential types are okay

  auto nominal = type->getAnyNominal();

  if (auto classDecl = dyn_cast_or_null<ClassDecl>(nominal)) {
    if (classDecl->isObjC())
      return None; // @objc class types are okay.
    return diag::iboutlet_nonobjc_class;
  }

  if (nominal == TC.Context.getStringDecl()) {
    // String is okay because it is bridged to NSString.
    // FIXME: BridgesTypes.def is almost sufficient for this.
    return None;
  }

  if (nominal == TC.Context.getArrayDecl()) {
    // Arrays of arrays are not allowed.
    if (isArray)
      return diag::iboutlet_nonobject_type;

    isArray = true;

    // Handle Array<T>. T must be an Objective-C class or protocol.
    auto boundTy = type->castTo<BoundGenericStructType>();
    auto boundArgs = boundTy->getGenericArgs();
    assert(boundArgs.size() == 1 && "invalid Array declaration");
    Type elementTy = boundArgs.front();
    return isAcceptableOutletType(elementTy, isArray, TC);
  }

  if (type->isExistentialType())
    return diag::iboutlet_nonobjc_protocol;
  
  // No other types are permitted.
  return diag::iboutlet_nonobject_type;
}


void AttributeEarlyChecker::visitIBOutletAttr(IBOutletAttr *attr) {
  // Only instance properties can be 'IBOutlet'.
  auto *VD = cast<VarDecl>(D);
  if (!VD->getDeclContext()->getSelfClassDecl() || VD->isStatic())
    diagnoseAndRemoveAttr(attr, diag::invalid_iboutlet);

  if (!VD->isSettable(nullptr))
    diagnoseAndRemoveAttr(attr, diag::iboutlet_only_mutable);

  // Verify that the field type is valid as an outlet.
  auto type = VD->getType();

  if (VD->isInvalid())
    return;

  // Look through ownership types, and optionals.
  type = type->getReferenceStorageReferent();
  bool wasOptional = false;
  if (Type underlying = type->getOptionalObjectType()) {
    type = underlying;
    wasOptional = true;
  }

  bool isArray = false;
  if (auto isError = isAcceptableOutletType(type, isArray, TC))
    diagnoseAndRemoveAttr(attr, isError.getValue(),
                                 /*array=*/isArray, type);

  // If the type wasn't optional, an array, or unowned, complain.
  if (!wasOptional && !isArray) {
    TC.diagnose(attr->getLocation(), diag::iboutlet_non_optional, type);
    auto typeRange = VD->getTypeSourceRangeForDiagnostics();
    { // Only one diagnostic can be active at a time.
      auto diag = TC.diagnose(typeRange.Start, diag::note_make_optional,
                              OptionalType::get(type));
      if (type->hasSimpleTypeRepr()) {
        diag.fixItInsertAfter(typeRange.End, "?");
      } else {
        diag.fixItInsert(typeRange.Start, "(")
          .fixItInsertAfter(typeRange.End, ")?");
      }
    }
    { // Only one diagnostic can be active at a time.
      auto diag = TC.diagnose(typeRange.Start,
                              diag::note_make_implicitly_unwrapped_optional);
      if (type->hasSimpleTypeRepr()) {
        diag.fixItInsertAfter(typeRange.End, "!");
      } else {
        diag.fixItInsert(typeRange.Start, "(")
          .fixItInsertAfter(typeRange.End, ")!");
      }
    }
  }
}

void AttributeEarlyChecker::visitNSManagedAttr(NSManagedAttr *attr) {
  // @NSManaged only applies to instance methods and properties within a class.
  if (cast<ValueDecl>(D)->isStatic() ||
      !D->getDeclContext()->getSelfClassDecl()) {
    diagnoseAndRemoveAttr(attr, diag::attr_NSManaged_not_instance_member);
  }

  if (auto *method = dyn_cast<FuncDecl>(D)) {
    // Separate out the checks for methods.
    if (method->hasBody())
      diagnoseAndRemoveAttr(attr, diag::attr_NSManaged_method_body);

    return;
  }

  // Everything below deals with restrictions on @NSManaged properties.
  auto *VD = cast<VarDecl>(D);

  if (VD->isLet())
    diagnoseAndRemoveAttr(attr, diag::attr_NSManaged_let_property);

  auto diagnoseNotStored = [&](unsigned kind) {
    TC.diagnose(attr->getLocation(), diag::attr_NSManaged_not_stored, kind);
    return attr->setInvalid();
  };

  // @NSManaged properties must be written as stored.
  auto impl = VD->getImplInfo();
  if (impl.isSimpleStored()) {
    // @NSManaged properties end up being computed; complain if there is
    // an initializer.
    if (VD->getParentInitializer()) {
      TC.diagnose(attr->getLocation(), diag::attr_NSManaged_initial_value)
        .highlight(VD->getParentInitializer()->getSourceRange());
      auto PBD = VD->getParentPatternBinding();
      PBD->setInit(PBD->getPatternEntryIndexForVarDecl(VD), nullptr);
    }
    // Otherwise, ok.
  } else if (impl.getReadImpl() == ReadImplKind::Address ||
             impl.getWriteImpl() == WriteImplKind::MutableAddress) {
    return diagnoseNotStored(/*addressed*/ 2);    
  } else if (impl.getWriteImpl() == WriteImplKind::StoredWithObservers ||
             impl.getWriteImpl() == WriteImplKind::InheritedWithObservers) {
    return diagnoseNotStored(/*observing*/ 1);    
  } else {
    return diagnoseNotStored(/*computed*/ 0);
  }

  // @NSManaged properties cannot be @NSCopying
  if (auto *NSCopy = VD->getAttrs().getAttribute<NSCopyingAttr>())
    diagnoseAndRemoveAttr(NSCopy, diag::attr_NSManaged_NSCopying);

}

void AttributeEarlyChecker::
visitLLDBDebuggerFunctionAttr(LLDBDebuggerFunctionAttr *attr) {
  // This is only legal when debugger support is on.
  if (!D->getASTContext().LangOpts.DebuggerSupport)
    diagnoseAndRemoveAttr(attr, diag::attr_for_debugger_support_only);
}

void AttributeEarlyChecker::visitOverrideAttr(OverrideAttr *attr) {
  if (!isa<ClassDecl>(D->getDeclContext()) &&
      !isa<ProtocolDecl>(D->getDeclContext()) &&
      !isa<ExtensionDecl>(D->getDeclContext()))
    diagnoseAndRemoveAttr(attr, diag::override_nonclass_decl);
}

void AttributeEarlyChecker::visitNonOverrideAttr(NonOverrideAttr *attr) {
  if (!isa<ClassDecl>(D->getDeclContext()) &&
      !isa<ProtocolDecl>(D->getDeclContext()) &&
      !isa<ExtensionDecl>(D->getDeclContext()))
    diagnoseAndRemoveAttr(attr, diag::nonoverride_wrong_decl_context);
}

void AttributeEarlyChecker::visitLazyAttr(LazyAttr *attr) {
  // lazy may only be used on properties.
  auto *VD = cast<VarDecl>(D);

  // It cannot currently be used on let's since we don't have a mutability model
  // that supports it.
  if (VD->isLet())
    diagnoseAndRemoveAttr(attr, diag::lazy_not_on_let);

  auto attrs = VD->getAttrs();
  // 'lazy' is not allowed to have reference attributes
  if (auto *refAttr = attrs.getAttribute<ReferenceOwnershipAttr>())
    diagnoseAndRemoveAttr(attr, diag::lazy_not_strong, refAttr->get());

  // lazy is not allowed on a protocol requirement.
  auto varDC = VD->getDeclContext();
  if (isa<ProtocolDecl>(varDC))
    diagnoseAndRemoveAttr(attr, diag::lazy_not_in_protocol);


  // 'lazy' is not allowed on a global variable or on a static property (which
  // are already lazily initialized).
  // TODO: we can't currently support lazy properties on non-type-contexts.
  if (VD->isStatic() ||
      (varDC->isModuleScopeContext() &&
       !varDC->getParentSourceFile()->isScriptMode())) {
    diagnoseAndRemoveAttr(attr, diag::lazy_on_already_lazy_global);
  } else if (!VD->getDeclContext()->isTypeContext()) {
    diagnoseAndRemoveAttr(attr, diag::lazy_must_be_property);
  }

  // lazy must have an initializer, and the pattern binding must be a simple
  // one.
  if (!VD->getParentInitializer())
    diagnoseAndRemoveAttr(attr, diag::lazy_requires_initializer);

  if (!VD->getParentPatternBinding()->getSingleVar())
    diagnoseAndRemoveAttr(attr, diag::lazy_requires_single_var);


  // TODO: Lazy properties can't yet be observed.
  auto impl = VD->getImplInfo();
  if (impl.isSimpleStored()) {
    // ok
  } else if (VD->hasStorage()) {
    diagnoseAndRemoveAttr(attr, diag::lazy_not_observable);
  } else {
    diagnoseAndRemoveAttr(attr, diag::lazy_not_on_computed);
  }
}

bool AttributeEarlyChecker::visitAbstractAccessControlAttr(
    AbstractAccessControlAttr *attr) {
  // Access control attr may only be used on value decls and extensions.
  if (!isa<ValueDecl>(D) && !isa<ExtensionDecl>(D)) {
    diagnoseAndRemoveAttr(attr, diag::invalid_decl_modifier, attr);
    return true;
  }

  if (auto extension = dyn_cast<ExtensionDecl>(D)) {
    if (!extension->getInherited().empty()) {
      diagnoseAndRemoveAttr(attr, diag::extension_access_with_conformances,
                            attr);
      return true;
    }
  }

  // And not on certain value decls.
  if (isa<DestructorDecl>(D) || isa<EnumElementDecl>(D)) {
    diagnoseAndRemoveAttr(attr, diag::invalid_decl_modifier, attr);
    return true;
  }

  // Or within protocols.
  if (isa<ProtocolDecl>(D->getDeclContext())) {
    diagnoseAndRemoveAttr(attr, diag::access_control_in_protocol, attr);
    TC.diagnose(attr->getLocation(), diag::access_control_in_protocol_detail);
    return true;
  }

  return false;
}

void AttributeEarlyChecker::visitAccessControlAttr(AccessControlAttr *attr) {
  visitAbstractAccessControlAttr(attr);
}

void AttributeEarlyChecker::visitSetterAccessAttr(
    SetterAccessAttr *attr) {
  auto storage = dyn_cast<AbstractStorageDecl>(D);
  if (!storage)
    diagnoseAndRemoveAttr(attr, diag::access_control_setter, attr->getAccess());

  if (visitAbstractAccessControlAttr(attr))
    return;

  if (!storage->isSettable(storage->getDeclContext())) {
    // This must stay in sync with diag::access_control_setter_read_only.
    enum {
      SK_Constant = 0,
      SK_Variable,
      SK_Property,
      SK_Subscript
    } storageKind;
    if (isa<SubscriptDecl>(storage))
      storageKind = SK_Subscript;
    else if (storage->getDeclContext()->isTypeContext())
      storageKind = SK_Property;
    else if (cast<VarDecl>(storage)->isImmutable())
      storageKind = SK_Constant;
    else
      storageKind = SK_Variable;
    diagnoseAndRemoveAttr(attr, diag::access_control_setter_read_only,
                          attr->getAccess(), storageKind);
  }
}

void AttributeEarlyChecker::visitObjCMembersAttr(ObjCMembersAttr *attr) {
  if (!isa<ClassDecl>(D))
    diagnoseAndRemoveAttr(attr, diag::objcmembers_attribute_nonclass);
}

void TypeChecker::checkDeclAttributesEarly(Decl *D) {
  // Don't perform early attribute validation more than once.
  // FIXME: Crummy way to get idempotency.
  if (D->didEarlyAttrValidation())
    return;

  D->setEarlyAttrValidation();

  AttributeEarlyChecker Checker(*this, D);
  for (auto attr : D->getAttrs()) {
    if (!attr->isValid()) continue;

    // If Attr.def says that the attribute cannot appear on this kind of
    // declaration, diagnose it and disable it.
    if (attr->canAppearOnDecl(D)) {
      // Otherwise, check it.
      Checker.visit(attr);
      continue;
    }

    // Otherwise, this attribute cannot be applied to this declaration.  If the
    // attribute is only valid on one kind of declaration (which is pretty
    // common) give a specific helpful error.
    auto PossibleDeclKinds = attr->getOptions() & DeclAttribute::OnAnyDecl;
    StringRef OnlyKind;
    switch (PossibleDeclKinds) {
    case DeclAttribute::OnAccessor:    OnlyKind = "accessor"; break;
    case DeclAttribute::OnClass:       OnlyKind = "class"; break;
    case DeclAttribute::OnConstructor: OnlyKind = "init"; break;
    case DeclAttribute::OnDestructor:  OnlyKind = "deinit"; break;
    case DeclAttribute::OnEnum:        OnlyKind = "enum"; break;
    case DeclAttribute::OnEnumCase:    OnlyKind = "case"; break;
    case DeclAttribute::OnFunc | DeclAttribute::OnAccessor: // FIXME
    case DeclAttribute::OnFunc:        OnlyKind = "func"; break;
    case DeclAttribute::OnImport:      OnlyKind = "import"; break;
    case DeclAttribute::OnModule:      OnlyKind = "module"; break;
    case DeclAttribute::OnParam:       OnlyKind = "parameter"; break;
    case DeclAttribute::OnProtocol:    OnlyKind = "protocol"; break;
    case DeclAttribute::OnStruct:      OnlyKind = "struct"; break;
    case DeclAttribute::OnSubscript:   OnlyKind = "subscript"; break;
    case DeclAttribute::OnTypeAlias:   OnlyKind = "typealias"; break;
    case DeclAttribute::OnVar:         OnlyKind = "var"; break;
    default: break;
    }

    if (!OnlyKind.empty())
      Checker.diagnoseAndRemoveAttr(attr, diag::attr_only_one_decl_kind,
                                    attr, OnlyKind);
    else if (attr->isDeclModifier())
      Checker.diagnoseAndRemoveAttr(attr, diag::invalid_decl_modifier, attr);
    else
      Checker.diagnoseAndRemoveAttr(attr, diag::invalid_decl_attribute, attr);
  }
}

namespace {
class AttributeChecker : public AttributeVisitor<AttributeChecker> {
  TypeChecker &TC;
  Decl *D;

  /// This emits a diagnostic with a fixit to remove the attribute.
  template<typename ...ArgTypes>
  void diagnoseAndRemoveAttr(DeclAttribute *attr, ArgTypes &&...Args) {
    ::diagnoseAndRemoveAttr(TC, D, attr, std::forward<ArgTypes>(Args)...);
  }

public:
  AttributeChecker(TypeChecker &TC, Decl *D) : TC(TC), D(D) {}

  /// Deleting this ensures that all attributes are covered by the visitor
  /// below.
  void visitDeclAttribute(DeclAttribute *A) = delete;

#define IGNORED_ATTR(CLASS)                                              \
    void visit##CLASS##Attr(CLASS##Attr *) {}

    IGNORED_ATTR(Alignment)
    IGNORED_ATTR(Borrowed)
    IGNORED_ATTR(HasInitialValue)
    IGNORED_ATTR(ClangImporterSynthesizedType)
    IGNORED_ATTR(Consuming)
    IGNORED_ATTR(Convenience)
    IGNORED_ATTR(Dynamic)
    IGNORED_ATTR(Effects)
    IGNORED_ATTR(Exported)
    IGNORED_ATTR(ForbidSerializingReference)
    IGNORED_ATTR(GKInspectable)
    IGNORED_ATTR(HasStorage)
    IGNORED_ATTR(IBDesignable)
    IGNORED_ATTR(IBInspectable)
    IGNORED_ATTR(IBOutlet) // checked early.
    IGNORED_ATTR(ImplicitlyUnwrappedOptional)
    IGNORED_ATTR(Indirect)
    IGNORED_ATTR(Inline)
    IGNORED_ATTR(Lazy)      // checked early.
    IGNORED_ATTR(LLDBDebuggerFunction)
    IGNORED_ATTR(Mutating)
    IGNORED_ATTR(NonMutating)
    IGNORED_ATTR(NonObjC)
    IGNORED_ATTR(NoReturn)
    IGNORED_ATTR(NSManaged) // checked early.
    IGNORED_ATTR(ObjC)
    IGNORED_ATTR(ObjCBridged)
    IGNORED_ATTR(ObjCMembers)
    IGNORED_ATTR(ObjCNonLazyRealization)
    IGNORED_ATTR(ObjCRuntimeName)
    IGNORED_ATTR(Optional)
    IGNORED_ATTR(Override)
    IGNORED_ATTR(RawDocComment)
    IGNORED_ATTR(ReferenceOwnership)
    IGNORED_ATTR(RequiresStoredPropertyInits)
    IGNORED_ATTR(RestatedObjCConformance)
    IGNORED_ATTR(Semantics)
    IGNORED_ATTR(ShowInInterface)
    IGNORED_ATTR(SILGenName)
    IGNORED_ATTR(StaticInitializeObjCMetadata)
    IGNORED_ATTR(SynthesizedProtocol)
    IGNORED_ATTR(Testable)
    IGNORED_ATTR(Transparent)
    IGNORED_ATTR(WarnUnqualifiedAccess)
    IGNORED_ATTR(WeakLinked)
    IGNORED_ATTR(DynamicReplacement)
    IGNORED_ATTR(PrivateImport)
#undef IGNORED_ATTR

  void visitAvailableAttr(AvailableAttr *attr);
  
  void visitCDeclAttr(CDeclAttr *attr);

  void visitDynamicCallableAttr(DynamicCallableAttr *attr);

  void visitDynamicMemberLookupAttr(DynamicMemberLookupAttr *attr);
  
  void visitFinalAttr(FinalAttr *attr);
  void visitIBActionAttr(IBActionAttr *attr);
  void visitNSCopyingAttr(NSCopyingAttr *attr);
  void visitRequiredAttr(RequiredAttr *attr);
  void visitRethrowsAttr(RethrowsAttr *attr);

  void visitAccessControlAttr(AccessControlAttr *attr);
  void visitSetterAccessAttr(SetterAccessAttr *attr);

  void checkApplicationMainAttribute(DeclAttribute *attr,
                                     Identifier Id_ApplicationDelegate,
                                     Identifier Id_Kit,
                                     Identifier Id_ApplicationMain);
  
  void visitNSApplicationMainAttr(NSApplicationMainAttr *attr);
  void visitUIApplicationMainAttr(UIApplicationMainAttr *attr);

  void visitUnsafeNoObjCTaggedPointerAttr(UnsafeNoObjCTaggedPointerAttr *attr);
  void visitSwiftNativeObjCRuntimeBaseAttr(
                                         SwiftNativeObjCRuntimeBaseAttr *attr);

  void checkOperatorAttribute(DeclAttribute *attr);

  void visitInfixAttr(InfixAttr *attr) { checkOperatorAttribute(attr); }
  void visitPostfixAttr(PostfixAttr *attr) { checkOperatorAttribute(attr); }
  void visitPrefixAttr(PrefixAttr *attr) { checkOperatorAttribute(attr); }

  void visitSpecializeAttr(SpecializeAttr *attr);

  void visitFixedLayoutAttr(FixedLayoutAttr *attr);
  void visitUsableFromInlineAttr(UsableFromInlineAttr *attr);
  void visitInlinableAttr(InlinableAttr *attr);
  void visitOptimizeAttr(OptimizeAttr *attr);

  void visitDiscardableResultAttr(DiscardableResultAttr *attr);
  void visitImplementsAttr(ImplementsAttr *attr);

  void visitFrozenAttr(FrozenAttr *attr);

  void visitNonOverrideAttr(NonOverrideAttr *attr);

  // SWIFT_ENABLE_TENSORFLOW
  void visitDifferentiableAttr(DifferentiableAttr *attr);
  void visitDifferentiatingAttr(DifferentiatingAttr *attr);
  void visitCompilerEvaluableAttr(CompilerEvaluableAttr *attr);
  void visitTensorFlowGraphAttr(TensorFlowGraphAttr *attr);
  void visitFieldwiseDifferentiableAttr(FieldwiseDifferentiableAttr *attr);
  void visitNoDerivativeAttr(NoDerivativeAttr *attr);
};
} // end anonymous namespace


static bool checkObjectOrOptionalObjectType(TypeChecker &TC, Decl *D,
                                            ParamDecl *param) {
  Type ty = param->getType();
  if (auto unwrapped = ty->getOptionalObjectType())
    ty = unwrapped;

  if (auto classDecl = ty->getClassOrBoundGenericClass()) {
    // @objc class types are okay.
    if (!classDecl->isObjC()) {
      TC.diagnose(D, diag::ibaction_nonobjc_class_argument,
                  param->getType())
        .highlight(param->getSourceRange());
      return true;
    }
  } else if (ty->isObjCExistentialType() || ty->isAny()) {
    // @objc existential types are okay, as is Any.
    // Nothing to do.
  } else {
    // No other types are permitted.
    TC.diagnose(D, diag::ibaction_nonobject_argument,
                param->getType())
      .highlight(param->getSourceRange());
    return true;
  }

  return false;
}

static bool isiOS(TypeChecker &TC) {
  return TC.getLangOpts().Target.isiOS();
}

static bool iswatchOS(TypeChecker &TC) {
  return TC.getLangOpts().Target.isWatchOS();
}

static bool isRelaxedIBAction(TypeChecker &TC) {
  return isiOS(TC) || iswatchOS(TC);
}

/// Returns true if the given method is an valid implementation of a
/// @dynamicCallable attribute requirement. The method is given to be defined
/// as one of the following: `dynamicallyCall(withArguments:)` or
/// `dynamicallyCall(withKeywordArguments:)`.
bool swift::isValidDynamicCallableMethod(FuncDecl *decl, DeclContext *DC,
                                         TypeChecker &TC,
                                         bool hasKeywordArguments) {
  // There are two cases to check.
  // 1. `dynamicallyCall(withArguments:)`.
  //    In this case, the method is valid if the argument has type `A` where
  //    `A` conforms to `ExpressibleByArrayLiteral`.
  //    `A.ArrayLiteralElement` and the return type can be arbitrary.
  // 2. `dynamicallyCall(withKeywordArguments:)`
  //    In this case, the method is valid if the argument has type `D` where
  //    `D` conforms to `ExpressibleByDictionaryLiteral` and `D.Key` conforms to
  //    `ExpressibleByStringLiteral`.
  //    `D.Value` and the return type can be arbitrary.

  TC.validateDeclForNameLookup(decl);
  auto paramList = decl->getParameters();
  if (paramList->size() != 1 || paramList->get(0)->isVariadic()) return false;
  auto argType = paramList->get(0)->getType();

  // If non-keyword (positional) arguments, check that argument type conforms to
  // `ExpressibleByArrayLiteral`.
  if (!hasKeywordArguments) {
    auto arrayLitProto =
      TC.Context.getProtocol(KnownProtocolKind::ExpressibleByArrayLiteral);
    return TC.conformsToProtocol(argType, arrayLitProto, DC,
                                 ConformanceCheckOptions()).hasValue();
  }
  // If keyword arguments, check that argument type conforms to
  // `ExpressibleByDictionaryLiteral` and that the `Key` associated type
  // conforms to `ExpressibleByStringLiteral`.
  auto stringLitProtocol =
    TC.Context.getProtocol(KnownProtocolKind::ExpressibleByStringLiteral);
  auto dictLitProto =
    TC.Context.getProtocol(KnownProtocolKind::ExpressibleByDictionaryLiteral);
  auto dictConf = TC.conformsToProtocol(argType, dictLitProto, DC,
                                        ConformanceCheckOptions());
  if (!dictConf) return false;
  auto lookup = dictLitProto->lookupDirect(TC.Context.Id_Key);
  auto keyAssocType =
    cast<AssociatedTypeDecl>(lookup[0])->getDeclaredInterfaceType();
  auto keyType = dictConf.getValue().getAssociatedType(argType, keyAssocType);
  return TC.conformsToProtocol(keyType, stringLitProtocol, DC,
                               ConformanceCheckOptions()).hasValue();
}

/// Returns true if the given nominal type has a valid implementation of a
/// @dynamicCallable attribute requirement with the given argument name.
static bool hasValidDynamicCallableMethod(TypeChecker &TC,
                                          NominalTypeDecl *decl,
                                          Identifier argumentName,
                                          bool hasKeywordArgs) {
  auto declType = decl->getDeclaredType();
  auto methodName = DeclName(TC.Context,
                             DeclBaseName(TC.Context.Id_dynamicallyCall),
                             { argumentName });
  auto candidates = TC.lookupMember(decl, declType, methodName);
  if (candidates.empty()) return false;

  // Filter valid candidates.
  candidates.filter([&](LookupResultEntry entry, bool isOuter) {
    auto candidate = cast<FuncDecl>(entry.getValueDecl());
    return isValidDynamicCallableMethod(candidate, decl, TC, hasKeywordArgs);
  });

  // If there are no valid candidates, return false.
  if (candidates.size() == 0) return false;
  return true;
}

void AttributeChecker::
visitDynamicCallableAttr(DynamicCallableAttr *attr) {
  // This attribute is only allowed on nominal types.
  auto decl = cast<NominalTypeDecl>(D);
  auto type = decl->getDeclaredType();

  bool hasValidMethod = false;
  hasValidMethod |=
    hasValidDynamicCallableMethod(TC, decl, TC.Context.Id_withArguments,
                                  /*hasKeywordArgs*/ false);
  hasValidMethod |=
    hasValidDynamicCallableMethod(TC, decl, TC.Context.Id_withKeywordArguments,
                                  /*hasKeywordArgs*/ true);
  if (!hasValidMethod) {
    TC.diagnose(attr->getLocation(), diag::invalid_dynamic_callable_type, type);
    attr->setInvalid();
  }
}

/// Returns true if the given subscript method is an valid implementation of
/// the `subscript(dynamicMember:)` requirement for @dynamicMemberLookup.
/// The method is given to be defined as `subscript(dynamicMember:)`.
bool swift::isValidDynamicMemberLookupSubscript(SubscriptDecl *decl,
                                                DeclContext *DC,
                                                TypeChecker &TC) {
  // There are two requirements:
  // - The subscript method has exactly one, non-variadic parameter.
  // - The parameter type conforms to `ExpressibleByStringLiteral`.
  auto indices = decl->getIndices();

  auto stringLitProto =
    TC.Context.getProtocol(KnownProtocolKind::ExpressibleByStringLiteral);
  
  return indices->size() == 1 && !indices->get(0)->isVariadic() &&
    TC.conformsToProtocol(indices->get(0)->getType(),
                          stringLitProto, DC, ConformanceCheckOptions());
}

/// The @dynamicMemberLookup attribute is only allowed on types that have at
/// least one subscript member declared like this:
///
/// subscript<KeywordType: ExpressibleByStringLiteral, LookupValue>
///   (dynamicMember name: KeywordType) -> LookupValue { get }
///
/// ... but doesn't care about the mutating'ness of the getter/setter.
/// We just manually check the requirements here.
void AttributeChecker::
visitDynamicMemberLookupAttr(DynamicMemberLookupAttr *attr) {
  // This attribute is only allowed on nominal types.
  auto decl = cast<NominalTypeDecl>(D);
  auto type = decl->getDeclaredType();
  
  // Look up `subscript(dynamicMember:)` candidates.
  auto subscriptName = DeclName(TC.Context, DeclBaseName::createSubscript(),
                                TC.Context.Id_dynamicMember);
  auto candidates = TC.lookupMember(decl, type, subscriptName);
  
  // If there are no candidates, then the attribute is invalid.
  if (candidates.empty()) {
    TC.diagnose(attr->getLocation(), diag::invalid_dynamic_member_lookup_type,
                type);
    attr->setInvalid();
    return;
  }

  // If no candidates are valid, then reject one.
  auto oneCandidate = candidates.front();
  candidates.filter([&](LookupResultEntry entry, bool isOuter) -> bool {
    auto cand = cast<SubscriptDecl>(entry.getValueDecl());
    TC.validateDeclForNameLookup(cand);
    return isValidDynamicMemberLookupSubscript(cand, decl, TC);
  });

  if (candidates.empty()) {
    TC.diagnose(oneCandidate.getValueDecl()->getLoc(),
                diag::invalid_dynamic_member_lookup_type, type);
    attr->setInvalid();
  }
}

void AttributeChecker::visitIBActionAttr(IBActionAttr *attr) {
  // IBActions instance methods must have type Class -> (...) -> ().
  auto *FD = cast<FuncDecl>(D);
  Type CurriedTy = FD->getMethodInterfaceType();
  Type ResultTy = CurriedTy->castTo<AnyFunctionType>()->getResult();
  if (!ResultTy->isEqual(TupleType::getEmpty(TC.Context))) {
    TC.diagnose(D, diag::invalid_ibaction_result, ResultTy);
    attr->setInvalid();
    return;
  }

  auto paramList = FD->getParameters();
  bool relaxedIBActionUsedOnOSX = false;
  bool Valid = true;
  switch (paramList->size()) {
  case 0:
    // (iOS only) No arguments.
    if (!isRelaxedIBAction(TC)) {
      relaxedIBActionUsedOnOSX = true;
      break;
    }
    break;
  case 1:
    // One argument. May be a scalar on iOS/watchOS (because of WatchKit).
    if (isRelaxedIBAction(TC)) {
      // Do a rough check to allow any ObjC-representable struct or enum type
      // on iOS.
      Type ty = paramList->get(0)->getType();
      if (auto nominal = ty->getAnyNominal())
        if (isa<StructDecl>(nominal) || isa<EnumDecl>(nominal))
          if (!nominal->isOptionalDecl())
            if (ty->isTriviallyRepresentableIn(ForeignLanguage::ObjectiveC,
                                               cast<FuncDecl>(D)))
              break;  // Looks ok.
    }
    if (checkObjectOrOptionalObjectType(TC, D, paramList->get(0)))
      Valid = false;
    break;
  case 2:
    // (iOS/watchOS only) Two arguments, the second of which is a UIEvent.
    // We don't currently enforce the UIEvent part.
    if (!isRelaxedIBAction(TC)) {
      relaxedIBActionUsedOnOSX = true;
      break;
    }
    if (checkObjectOrOptionalObjectType(TC, D, paramList->get(0)))
      Valid = false;
    if (checkObjectOrOptionalObjectType(TC, D, paramList->get(1)))
      Valid = false;
    break;
  default:
    // No platform allows an action signature with more than two arguments.
    TC.diagnose(D, diag::invalid_ibaction_argument_count,
                isRelaxedIBAction(TC));
    Valid = false;
    break;
  }

  if (relaxedIBActionUsedOnOSX) {
    TC.diagnose(D, diag::invalid_ibaction_argument_count,
                /*relaxedIBAction=*/false);
    Valid = false;
  }

  if (!Valid)
    attr->setInvalid();
}

/// Get the innermost enclosing declaration for a declaration.
static Decl *getEnclosingDeclForDecl(Decl *D) {
  // If the declaration is an accessor, treat its storage declaration
  // as the enclosing declaration.
  if (auto *accessor = dyn_cast<AccessorDecl>(D)) {
    return accessor->getStorage();
  }

  return D->getDeclContext()->getInnermostDeclarationDeclContext();
}

void AttributeChecker::visitAvailableAttr(AvailableAttr *attr) {
  if (TC.getLangOpts().DisableAvailabilityChecking)
    return;

  if (!attr->hasPlatform() || !attr->isActivePlatform(TC.Context) ||
      !attr->Introduced.hasValue()) {
    return;
  }

  SourceLoc attrLoc = attr->getLocation();

  Optional<Diag<>> MaybeNotAllowed =
      TC.diagnosticIfDeclCannotBePotentiallyUnavailable(D);
  if (MaybeNotAllowed.hasValue()) {
    TC.diagnose(attrLoc, MaybeNotAllowed.getValue());
  }

  // Find the innermost enclosing declaration with an availability
  // range annotation and ensure that this attribute's available version range
  // is fully contained within that declaration's range. If there is no such
  // enclosing declaration, then there is nothing to check.
  Optional<AvailabilityContext> EnclosingAnnotatedRange;
  Decl *EnclosingDecl = getEnclosingDeclForDecl(D);

  while (EnclosingDecl) {
    EnclosingAnnotatedRange =
        AvailabilityInference::annotatedAvailableRange(EnclosingDecl,
                                                       TC.Context);

    if (EnclosingAnnotatedRange.hasValue())
      break;

    EnclosingDecl = getEnclosingDeclForDecl(EnclosingDecl);
  }

  if (!EnclosingDecl)
    return;

  AvailabilityContext AttrRange{
      VersionRange::allGTE(attr->Introduced.getValue())};

  if (!AttrRange.isContainedIn(EnclosingAnnotatedRange.getValue())) {
    TC.diagnose(attr->getLocation(),
                diag::availability_decl_more_than_enclosing);
    TC.diagnose(EnclosingDecl->getLoc(),
                diag::availability_decl_more_than_enclosing_enclosing_here);
  }
}

void AttributeChecker::visitCDeclAttr(CDeclAttr *attr) {
  // Only top-level func decls are currently supported.
  if (D->getDeclContext()->isTypeContext())
    TC.diagnose(attr->getLocation(),
                diag::cdecl_not_at_top_level);
  
  // The name must not be empty.
  if (attr->Name.empty())
    TC.diagnose(attr->getLocation(),
                diag::cdecl_empty_name);
}

void AttributeChecker::visitUnsafeNoObjCTaggedPointerAttr(
                                          UnsafeNoObjCTaggedPointerAttr *attr) {
  // Only class protocols can have the attribute.
  auto proto = dyn_cast<ProtocolDecl>(D);
  if (!proto) {
    TC.diagnose(attr->getLocation(),
                diag::no_objc_tagged_pointer_not_class_protocol);
    attr->setInvalid();
  }
  
  if (!proto->requiresClass()
      && !proto->getAttrs().hasAttribute<ObjCAttr>()) {
    TC.diagnose(attr->getLocation(),
                diag::no_objc_tagged_pointer_not_class_protocol);
    attr->setInvalid();    
  }
}

void AttributeChecker::visitSwiftNativeObjCRuntimeBaseAttr(
                                         SwiftNativeObjCRuntimeBaseAttr *attr) {
  // Only root classes can have the attribute.
  auto theClass = dyn_cast<ClassDecl>(D);
  if (!theClass) {
    TC.diagnose(attr->getLocation(),
                diag::swift_native_objc_runtime_base_not_on_root_class);
    attr->setInvalid();
    return;
  }
  
  if (theClass->hasSuperclass()) {
    TC.diagnose(attr->getLocation(),
                diag::swift_native_objc_runtime_base_not_on_root_class);
    attr->setInvalid();
    return;
  }
}

void AttributeChecker::visitFinalAttr(FinalAttr *attr) {
  // final on classes marks all members with final.
  if (isa<ClassDecl>(D))
    return;

  // We currently only support final on var/let, func and subscript
  // declarations.
  if (!isa<VarDecl>(D) && !isa<FuncDecl>(D) && !isa<SubscriptDecl>(D)) {
    TC.diagnose(attr->getLocation(), diag::final_not_allowed_here)
      .fixItRemove(attr->getRange());
    return;
  }

  if (auto *accessor = dyn_cast<AccessorDecl>(D)) {
    if (!attr->isImplicit()) {
      unsigned Kind = 2;
      if (auto *VD = dyn_cast<VarDecl>(accessor->getStorage()))
        Kind = VD->isLet() ? 1 : 0;
      TC.diagnose(attr->getLocation(), diag::final_not_on_accessors, Kind)
        .fixItRemove(attr->getRange());
      return;
    }
  }
}

/// Return true if this is a builtin operator that cannot be defined in user
/// code.
static bool isBuiltinOperator(StringRef name, DeclAttribute *attr) {
  return ((isa<PrefixAttr>(attr)  && name == "&") ||   // lvalue to inout
          (isa<PostfixAttr>(attr) && name == "!") ||   // optional unwrapping
          (isa<PostfixAttr>(attr) && name == "?") ||   // optional chaining
          (isa<InfixAttr>(attr) && name == "?") ||     // ternary operator
          (isa<PostfixAttr>(attr) && name == ">") ||   // generic argument list
          (isa<PrefixAttr>(attr)  && name == "<"));    // generic argument list
}

void AttributeChecker::checkOperatorAttribute(DeclAttribute *attr) {
  // Check out the operator attributes.  They may be attached to an operator
  // declaration or a function.
  if (auto *OD = dyn_cast<OperatorDecl>(D)) {
    // Reject attempts to define builtin operators.
    if (isBuiltinOperator(OD->getName().str(), attr)) {
      TC.diagnose(D->getStartLoc(), diag::redefining_builtin_operator,
                  attr->getAttrName(), OD->getName().str());
      attr->setInvalid();
      return;
    }

    // Otherwise, the attribute is always ok on an operator.
    return;
  }

  // Operators implementations may only be defined as functions.
  auto *FD = dyn_cast<FuncDecl>(D);
  if (!FD) {
    TC.diagnose(D->getLoc(), diag::operator_not_func);
    attr->setInvalid();
    return;
  }

  // Only functions with an operator identifier can be declared with as an
  // operator.
  if (!FD->isOperator()) {
    TC.diagnose(D->getStartLoc(), diag::attribute_requires_operator_identifier,
                attr->getAttrName());
    attr->setInvalid();
    return;
  }

  // Reject attempts to define builtin operators.
  if (isBuiltinOperator(FD->getName().str(), attr)) {
    TC.diagnose(D->getStartLoc(), diag::redefining_builtin_operator,
                attr->getAttrName(), FD->getName().str());
    attr->setInvalid();
    return;
  }

  // Otherwise, must be unary.
  if (!FD->isUnaryOperator()) {
    TC.diagnose(attr->getLocation(), diag::attribute_requires_single_argument,
                attr->getAttrName());
    attr->setInvalid();
    return;
  }
}

void AttributeChecker::visitNSCopyingAttr(NSCopyingAttr *attr) {
  // The @NSCopying attribute is only allowed on stored properties.
  auto *VD = cast<VarDecl>(D);

  // It may only be used on class members.
  auto classDecl = D->getDeclContext()->getSelfClassDecl();
  if (!classDecl) {
    TC.diagnose(attr->getLocation(), diag::nscopying_only_on_class_properties);
    attr->setInvalid();
    return;
  }

  if (!VD->isSettable(VD->getDeclContext())) {
    TC.diagnose(attr->getLocation(), diag::nscopying_only_mutable);
    attr->setInvalid();
    return;
  }

  if (!VD->hasStorage()) {
    TC.diagnose(attr->getLocation(), diag::nscopying_only_stored_property);
    attr->setInvalid();
    return;
  }

  if (VD->hasInterfaceType()) {
    if (TC.checkConformanceToNSCopying(VD)) {
      attr->setInvalid();
      return;
    }
  }

  assert(VD->getOverriddenDecl() == nullptr &&
         "Can't have value with storage that is an override");

  // Check the type.  It must be must be [unchecked]optional, weak, a normal
  // class, AnyObject, or classbound protocol.
  // must conform to the NSCopying protocol.
  
}

void AttributeChecker::checkApplicationMainAttribute(DeclAttribute *attr,
                                             Identifier Id_ApplicationDelegate,
                                             Identifier Id_Kit,
                                             Identifier Id_ApplicationMain) {
  // %select indexes for ApplicationMain diagnostics.
  enum : unsigned {
    UIApplicationMainClass,
    NSApplicationMainClass,
  };
  
  unsigned applicationMainKind;
  if (isa<UIApplicationMainAttr>(attr))
    applicationMainKind = UIApplicationMainClass;
  else if (isa<NSApplicationMainAttr>(attr))
    applicationMainKind = NSApplicationMainClass;
  else
    llvm_unreachable("not an ApplicationMain attr");
  
  auto *CD = dyn_cast<ClassDecl>(D);
  
  // The applicant not being a class should have been diagnosed by the early
  // checker.
  if (!CD) return;

  // The class cannot be generic.
  if (CD->isGenericContext()) {
    TC.diagnose(attr->getLocation(),
                diag::attr_generic_ApplicationMain_not_supported,
                applicationMainKind);
    attr->setInvalid();
    return;
  }
  
  // @XXApplicationMain classes must conform to the XXApplicationDelegate
  // protocol.
  auto &C = D->getASTContext();

  auto KitModule = C.getLoadedModule(Id_Kit);
  ProtocolDecl *ApplicationDelegateProto = nullptr;
  if (KitModule) {
    auto lookupOptions = defaultUnqualifiedLookupOptions;
    lookupOptions |= NameLookupFlags::KnownPrivate;

    auto lookup = TC.lookupUnqualifiedType(KitModule, Id_ApplicationDelegate,
                                           SourceLoc(),
                                           lookupOptions);
    if (lookup.size() == 1)
      ApplicationDelegateProto = dyn_cast<ProtocolDecl>(
        lookup[0].getValueDecl());
  }

  if (!ApplicationDelegateProto ||
      !TC.conformsToProtocol(CD->getDeclaredType(), ApplicationDelegateProto,
                             CD, None)) {
    TC.diagnose(attr->getLocation(),
                diag::attr_ApplicationMain_not_ApplicationDelegate,
                applicationMainKind);
    attr->setInvalid();
  }

  if (attr->isInvalid())
    return;
  
  // Register the class as the main class in the module. If there are multiples
  // they will be diagnosed.
  auto *SF = cast<SourceFile>(CD->getModuleScopeContext());
  if (SF->registerMainClass(CD, attr->getLocation()))
    attr->setInvalid();
  
  // Check that we have the needed symbols in the frameworks.
  auto lookupOptions = defaultUnqualifiedLookupOptions;
  lookupOptions |= NameLookupFlags::KnownPrivate;
  auto lookupMain = TC.lookupUnqualified(KitModule, Id_ApplicationMain,
                                         SourceLoc(), lookupOptions);

  for (const auto &result : lookupMain) {
    TC.validateDecl(result.getValueDecl());
  }
  auto Foundation = TC.Context.getLoadedModule(C.Id_Foundation);
  if (Foundation) {
    auto lookupString = TC.lookupUnqualified(
                          Foundation,
                          C.getIdentifier("NSStringFromClass"),
                          SourceLoc(),
                          lookupOptions);
    for (const auto &result : lookupString) {
      TC.validateDecl(result.getValueDecl());
    }
  }
}

void AttributeChecker::visitNSApplicationMainAttr(NSApplicationMainAttr *attr) {
  auto &C = D->getASTContext();
  checkApplicationMainAttribute(attr,
                                C.getIdentifier("NSApplicationDelegate"),
                                C.getIdentifier("AppKit"),
                                C.getIdentifier("NSApplicationMain"));
}
void AttributeChecker::visitUIApplicationMainAttr(UIApplicationMainAttr *attr) {
  auto &C = D->getASTContext();
  checkApplicationMainAttribute(attr,
                                C.getIdentifier("UIApplicationDelegate"),
                                C.getIdentifier("UIKit"),
                                C.getIdentifier("UIApplicationMain"));
}

/// Determine whether the given context is an extension to an Objective-C class
/// where the class is defined in the Objective-C module and the extension is
/// defined within its module.
static bool isObjCClassExtensionInOverlay(DeclContext *dc) {
  // Check whether we have an extension.
  auto ext = dyn_cast<ExtensionDecl>(dc);
  if (!ext)
    return false;

  // Find the extended class.
  auto classDecl = ext->getSelfClassDecl();
  if (!classDecl)
    return false;

  auto clangLoader = dc->getASTContext().getClangModuleLoader();
  if (!clangLoader) return false;
  return clangLoader->isInOverlayModuleForImportedModule(ext, classDecl);
}

void AttributeChecker::visitRequiredAttr(RequiredAttr *attr) {
  // The required attribute only applies to constructors.
  auto ctor = cast<ConstructorDecl>(D);
  auto parentTy = ctor->getDeclContext()->getDeclaredInterfaceType();
  if (!parentTy) {
    // Constructor outside of nominal type context; we've already complained
    // elsewhere.
    attr->setInvalid();
    return;
  }
  // Only classes can have required constructors.
  if (parentTy->getClassOrBoundGenericClass()) {
    // The constructor must be declared within the class itself.
    // FIXME: Allow an SDK overlay to add a required initializer to a class
    // defined in Objective-C
    if (!isa<ClassDecl>(ctor->getDeclContext()) &&
        !isObjCClassExtensionInOverlay(ctor->getDeclContext())) {
      TC.diagnose(ctor, diag::required_initializer_in_extension, parentTy)
        .highlight(attr->getLocation());
      attr->setInvalid();
      return;
    }
  } else {
    if (!parentTy->hasError()) {
      TC.diagnose(ctor, diag::required_initializer_nonclass, parentTy)
        .highlight(attr->getLocation());
    }
    attr->setInvalid();
    return;
  }
}

static bool hasThrowingFunctionParameter(CanType type) {
  // Only consider throwing function types.
  if (auto fnType = dyn_cast<AnyFunctionType>(type)) {
    return fnType->getExtInfo().throws();
  }

  // Look through tuples.
  if (auto tuple = dyn_cast<TupleType>(type)) {
    for (auto eltType : tuple.getElementTypes()) {
      if (hasThrowingFunctionParameter(eltType))
        return true;
    }
    return false;
  }

  // Suppress diagnostics in the presence of errors.
  if (type->hasError()) {
    return true;
  }

  return false;
}

void AttributeChecker::visitRethrowsAttr(RethrowsAttr *attr) {
  // 'rethrows' only applies to functions that take throwing functions
  // as parameters.
  auto fn = cast<AbstractFunctionDecl>(D);
  for (auto param : *fn->getParameters()) {
    if (hasThrowingFunctionParameter(param->getType()
            ->lookThroughAllOptionalTypes()
            ->getCanonicalType()))
      return;
  }

  TC.diagnose(attr->getLocation(), diag::rethrows_without_throwing_parameter);
  attr->setInvalid();
}

void AttributeChecker::visitAccessControlAttr(AccessControlAttr *attr) {
  if (auto extension = dyn_cast<ExtensionDecl>(D)) {
    if (attr->getAccess() == AccessLevel::Open) {
      TC.diagnose(attr->getLocation(), diag::access_control_extension_open)
        .fixItReplace(attr->getRange(), "public");
      attr->setInvalid();
      return;
    }

    NominalTypeDecl *nominal = extension->getExtendedNominal();
    AccessLevel typeAccess = nominal->getFormalAccess();
    if (attr->getAccess() > typeAccess) {
      TC.diagnose(attr->getLocation(), diag::access_control_extension_more,
                  typeAccess,
                  nominal->getDescriptiveKind(),
                  attr->getAccess())
        .fixItRemove(attr->getRange());
      attr->setInvalid();
      return;
    }

  } else if (auto extension = dyn_cast<ExtensionDecl>(D->getDeclContext())) {
    AccessLevel maxAccess = extension->getMaxAccessLevel();
    if (std::min(attr->getAccess(), AccessLevel::Public) > maxAccess) {
      // FIXME: It would be nice to say what part of the requirements actually
      // end up being problematic.
      auto diag =
          TC.diagnose(attr->getLocation(),
                      diag::access_control_ext_requirement_member_more,
                      attr->getAccess(),
                      D->getDescriptiveKind(),
                      maxAccess);
      swift::fixItAccess(diag, cast<ValueDecl>(D), maxAccess);
      return;
    }

    if (auto extAttr =
        extension->getAttrs().getAttribute<AccessControlAttr>()) {
      AccessLevel defaultAccess = extension->getDefaultAccessLevel();
      if (attr->getAccess() > defaultAccess) {
        auto diag = TC.diagnose(attr->getLocation(),
                                diag::access_control_ext_member_more,
                                attr->getAccess(),
                                D->getDescriptiveKind(),
                                extAttr->getAccess());
        swift::fixItAccess(diag, cast<ValueDecl>(D), defaultAccess, false,
                           true);
        return;
      } else if (attr->getAccess() == defaultAccess) {
        TC.diagnose(attr->getLocation(),
                    diag::access_control_ext_member_redundant,
                    attr->getAccess(),
                    D->getDescriptiveKind(),
                    extAttr->getAccess())
          .fixItRemove(attr->getRange());
        return;
      }
    }
  }

  if (attr->getAccess() == AccessLevel::Open) {
    if (!isa<ClassDecl>(D) && !D->isPotentiallyOverridable() &&
        !attr->isInvalid()) {
      TC.diagnose(attr->getLocation(), diag::access_control_open_bad_decl)
        .fixItReplace(attr->getRange(), "public");
      attr->setInvalid();
    }
  }
}

void
AttributeChecker::visitSetterAccessAttr(SetterAccessAttr *attr) {
  auto getterAccess = cast<ValueDecl>(D)->getFormalAccess();
  if (attr->getAccess() > getterAccess) {
    // This must stay in sync with diag::access_control_setter_more.
    enum {
      SK_Variable = 0,
      SK_Property,
      SK_Subscript
    } storageKind;
    if (isa<SubscriptDecl>(D))
      storageKind = SK_Subscript;
    else if (D->getDeclContext()->isTypeContext())
      storageKind = SK_Property;
    else
      storageKind = SK_Variable;
    TC.diagnose(attr->getLocation(), diag::access_control_setter_more,
                getterAccess, storageKind, attr->getAccess());
    attr->setInvalid();
    return;

  } else if (attr->getAccess() == getterAccess) {
    TC.diagnose(attr->getLocation(),
                diag::access_control_setter_redundant,
                attr->getAccess(),
                D->getDescriptiveKind(),
                getterAccess)
      .fixItRemove(attr->getRange());
    return;
  }
}

/// Collect all used generic parameter types from a given type.
static void collectUsedGenericParameters(
    Type Ty, SmallPtrSetImpl<TypeBase *> &ConstrainedGenericParams) {
  if (!Ty)
    return;

  if (!Ty->hasTypeParameter())
    return;

  // Add used generic parameters/archetypes.
  Ty.visit([&](Type Ty) {
    if (auto GP = dyn_cast<GenericTypeParamType>(Ty->getCanonicalType())) {
      ConstrainedGenericParams.insert(GP);
    }
  });
}

/// Perform some sanity checks for the requirements provided by
/// the @_specialize attribute.
static void checkSpecializeAttrRequirements(
    SpecializeAttr *attr,
    AbstractFunctionDecl *FD,
    const SmallPtrSet<TypeBase *, 4> &constrainedGenericParams,
    TypeChecker &TC) {
  auto genericSig = FD->getGenericSignature();

  if (!attr->isFullSpecialization())
    return;

  if (constrainedGenericParams.size() == genericSig->getGenericParams().size())
    return;

  TC.diagnose(
      attr->getLocation(), diag::specialize_attr_type_parameter_count_mismatch,
      genericSig->getGenericParams().size(), constrainedGenericParams.size(),
      constrainedGenericParams.size() < genericSig->getGenericParams().size());

  if (constrainedGenericParams.size() < genericSig->getGenericParams().size()) {
    // Figure out which archetypes are not constrained.
    for (auto gp : genericSig->getGenericParams()) {
      if (constrainedGenericParams.count(gp->getCanonicalType().getPointer()))
        continue;
      auto gpDecl = gp->getDecl();
      if (gpDecl) {
        TC.diagnose(attr->getLocation(),
                    diag::specialize_attr_missing_constraint,
                    gpDecl->getFullName());
      }
    }
  }
}

/// Retrieve the canonical version of the given requirement.
static Requirement getCanonicalRequirement(const Requirement &req) {
  switch (req.getKind()) {
  case RequirementKind::Conformance:
  case RequirementKind::SameType:
  case RequirementKind::Superclass:
    return Requirement(req.getKind(), req.getFirstType()->getCanonicalType(),
                       req.getSecondType()->getCanonicalType());

  case RequirementKind::Layout:
    return Requirement(req.getKind(), req.getFirstType()->getCanonicalType(),
                       req.getLayoutConstraint());
  }
  llvm_unreachable("unhandled kind");
}

/// Require that the given type either not involve type parameters or be
/// a type parameter.
static bool diagnoseIndirectGenericTypeParam(SourceLoc loc, Type type,
                                             TypeRepr *typeRepr) {
  if (type->hasTypeParameter() && !type->is<GenericTypeParamType>()) {
    type->getASTContext().Diags.diagnose(
        loc,
        diag::specialize_attr_only_generic_param_req)
      .highlight(typeRepr->getSourceRange());
    return true;
  }

  return false;
}

/// Type check that a set of requirements provided by @_specialize.
/// Store the set of requirements in the attribute.
void AttributeChecker::visitSpecializeAttr(SpecializeAttr *attr) {
  DeclContext *DC = D->getDeclContext();
  auto *FD = cast<AbstractFunctionDecl>(D);
  auto *genericSig = FD->getGenericSignature();
  auto *trailingWhereClause = attr->getTrailingWhereClause();

  if (!trailingWhereClause) {
    // Report a missing "where" clause.
    TC.diagnose(attr->getLocation(), diag::specialize_missing_where_clause);
    return;
  }

  if (trailingWhereClause->getRequirements().empty()) {
    // Report an empty "where" clause.
    TC.diagnose(attr->getLocation(), diag::specialize_empty_where_clause);
    return;
  }

  if (!genericSig) {
    // Only generic functions are permitted to have trailing where clauses.
    TC.diagnose(attr->getLocation(),
                diag::specialize_attr_nongeneric_trailing_where,
                FD->getFullName())
        .highlight(trailingWhereClause->getSourceRange());
    return;
  }

  // Form a new generic signature based on the old one.
  GenericSignatureBuilder Builder(D->getASTContext());

  // First, add the old generic signature.
  Builder.addGenericSignature(genericSig);

  // Set of generic parameters being constrained. It is used to
  // determine if a full specialization misses requirements for
  // some of the generic parameters.
  SmallPtrSet<TypeBase *, 4> constrainedGenericParams;

  // Go over the set of requirements, adding them to the builder.
  SmallVector<Requirement, 4> convertedRequirements;
  RequirementRequest::visitRequirements(
      WhereClauseOwner(FD, attr), TypeResolutionStage::Interface,
      [&](const Requirement &req, RequirementRepr *reqRepr) {
        // Collect all of the generic parameters used by these types.
        switch (req.getKind()) {
        case RequirementKind::Conformance:
        case RequirementKind::SameType:
        case RequirementKind::Superclass:
          collectUsedGenericParameters(req.getSecondType(),
                                       constrainedGenericParams);
          LLVM_FALLTHROUGH;

        case RequirementKind::Layout:
          collectUsedGenericParameters(req.getFirstType(),
                                       constrainedGenericParams);
          break;
        }

        // Check additional constraints.
        // FIXME: These likely aren't fundamental limitations.
        switch (req.getKind()) {
        case RequirementKind::SameType: {
          bool firstHasTypeParameter = req.getFirstType()->hasTypeParameter();
          bool secondHasTypeParameter = req.getSecondType()->hasTypeParameter();

          // Exactly one type can have a type parameter.
          if (firstHasTypeParameter == secondHasTypeParameter) {
            TC.diagnose(
                attr->getLocation(),
                firstHasTypeParameter
                  ? diag::specialize_attr_non_concrete_same_type_req
                  : diag::specialize_attr_only_one_concrete_same_type_req)
              .highlight(reqRepr->getSourceRange());
            return false;
          }

          // We either need a fully-concrete type or a generic type parameter.
          if (diagnoseIndirectGenericTypeParam(attr->getLocation(),
                                               req.getFirstType(),
                                               reqRepr->getFirstTypeRepr()) ||
              diagnoseIndirectGenericTypeParam(attr->getLocation(),
                                               req.getSecondType(),
                                               reqRepr->getSecondTypeRepr())) {
            return false;
          }
          break;
        }

        case RequirementKind::Superclass:
          TC.diagnose(attr->getLocation(),
                      diag::specialize_attr_non_protocol_type_constraint_req)
            .highlight(reqRepr->getSourceRange());
          return false;

        case RequirementKind::Conformance:
          if (diagnoseIndirectGenericTypeParam(attr->getLocation(),
                                               req.getFirstType(),
                                               reqRepr->getSubjectRepr())) {
            return false;
          }

          if (!req.getSecondType()->is<ProtocolType>()) {
            TC.diagnose(attr->getLocation(),
                        diag::specialize_attr_non_protocol_type_constraint_req)
              .highlight(reqRepr->getSourceRange());
            return false;
          }

          TC.diagnose(attr->getLocation(),
                      diag::specialize_attr_unsupported_kind_of_req)
            .highlight(reqRepr->getSourceRange());

          return false;

        case RequirementKind::Layout:
          if (diagnoseIndirectGenericTypeParam(attr->getLocation(),
                                               req.getFirstType(),
                                               reqRepr->getSubjectRepr())) {
            return false;
          }
          break;
        }

        // Add the requirement to the generic signature builder.
        using FloatingRequirementSource =
          GenericSignatureBuilder::FloatingRequirementSource;
        Builder.addRequirement(req, reqRepr,
                               FloatingRequirementSource::forExplicit(reqRepr),
                               nullptr, DC->getParentModule());
        convertedRequirements.push_back(getCanonicalRequirement(req));
        return false;
      });

  // Check the validity of provided requirements.
  checkSpecializeAttrRequirements(attr, FD, constrainedGenericParams, TC);

  // Store the converted requirements in the attribute so that
  // they are serialized later.
  attr->setRequirements(DC->getASTContext(), convertedRequirements);

  // Check the result.
  (void)std::move(Builder).computeGenericSignature(
                                        attr->getLocation(),
                                        /*allowConcreteGenericParams=*/true);
}

void AttributeChecker::visitFixedLayoutAttr(FixedLayoutAttr *attr) {
  auto *VD = cast<ValueDecl>(D);

  if (VD->getFormalAccess() < AccessLevel::Public &&
      !VD->getAttrs().hasAttribute<UsableFromInlineAttr>()) {
    diagnoseAndRemoveAttr(attr, diag::fixed_layout_attr_on_internal_type,
                          VD->getFullName(), VD->getFormalAccess());
  }
}

void AttributeChecker::visitUsableFromInlineAttr(UsableFromInlineAttr *attr) {
  auto *VD = cast<ValueDecl>(D);

  // FIXME: Once protocols can contain nominal types, do we want to allow
  // these nominal types to have access control (and also @usableFromInline)?
  if (isa<ProtocolDecl>(VD->getDeclContext())) {
    diagnoseAndRemoveAttr(attr, diag::usable_from_inline_attr_in_protocol);
    return;
  }

  // @usableFromInline can only be applied to internal declarations.
  if (VD->getFormalAccess() != AccessLevel::Internal) {
    diagnoseAndRemoveAttr(attr,
                          diag::usable_from_inline_attr_with_explicit_access,
                          VD->getFullName(),
                          VD->getFormalAccess());
    return;
  }

  // On internal declarations, @inlinable implies @usableFromInline.
  if (VD->getAttrs().hasAttribute<InlinableAttr>()) {
    if (TC.Context.isSwiftVersionAtLeast(4,2))
      diagnoseAndRemoveAttr(attr, diag::inlinable_implies_usable_from_inline);
    return;
  }
}

void AttributeChecker::visitInlinableAttr(InlinableAttr *attr) {
  // @inlinable cannot be applied to stored properties.
  //
  // If the type is fixed-layout, the accessors are inlinable anyway;
  // if the type is resilient, the accessors cannot be inlinable
  // because clients cannot directly access storage.
  if (auto *VD = dyn_cast<VarDecl>(D)) {
    if (VD->hasStorage() || VD->getAttrs().hasAttribute<LazyAttr>()) {
      diagnoseAndRemoveAttr(attr,
                            diag::attribute_invalid_on_stored_property,
                            attr);
      return;
    }
  }

  auto *VD = cast<ValueDecl>(D);

  // Calls to dynamically-dispatched declarations are never devirtualized,
  // so marking them as @inlinable does not make sense.
  if (VD->isDynamic()) {
    diagnoseAndRemoveAttr(attr, diag::inlinable_dynamic_not_supported);
    return;
  }

  // @inlinable can only be applied to public or internal declarations.
  auto access = VD->getFormalAccess();
  if (access < AccessLevel::Internal) {
    diagnoseAndRemoveAttr(attr, diag::inlinable_decl_not_public,
                          VD->getBaseName(),
                          access);
    return;
  }
}

void AttributeChecker::visitOptimizeAttr(OptimizeAttr *attr) {
  if (auto *VD = dyn_cast<VarDecl>(D)) {
    if (VD->hasStorage()) {
      diagnoseAndRemoveAttr(attr,
                            diag::attribute_invalid_on_stored_property,
                            attr);
      return;
    }
  }
}

void AttributeChecker::visitDiscardableResultAttr(DiscardableResultAttr *attr) {
  if (auto *FD = dyn_cast<FuncDecl>(D)) {
    if (auto result = FD->getResultInterfaceType()) {
      auto resultIsVoid = result->isVoid();
      if (resultIsVoid || result->isUninhabited()) {
        diagnoseAndRemoveAttr(attr,
                              diag::discardable_result_on_void_never_function,
                              resultIsVoid);
      }
    }
  }
}

/// Lookup the replaced decl in the replacments scope.
void lookupReplacedDecl(DeclName replacedDeclName,
                        DynamicReplacementAttr *attr,
                        AbstractFunctionDecl *replacement,
                        SmallVectorImpl<ValueDecl *> &results) {
  auto *declCtxt = replacement->getDeclContext();

  // Look at the accessors' storage's context.
  if (auto *accessor = dyn_cast<AccessorDecl>(replacement)) {
    auto *storage = accessor->getStorage();
    declCtxt = storage->getDeclContext();
  }

  if (isa<FileUnit>(declCtxt)) {
    UnqualifiedLookup lookup(replacedDeclName,
                             replacement->getModuleScopeContext(), nullptr,
                             attr->getLocation());
    if (lookup.isSuccess()) {
      for (auto entry : lookup.Results)
        results.push_back(entry.getValueDecl());
    }
    return;
  }

  assert(declCtxt->isTypeContext());
  auto typeCtx = dyn_cast<NominalTypeDecl>(declCtxt->getAsDecl());
  if (!typeCtx)
    typeCtx = cast<ExtensionDecl>(declCtxt->getAsDecl())->getExtendedNominal();

  replacement->getModuleScopeContext()->lookupQualified(
      {typeCtx}, replacedDeclName, NL_QualifiedDefault, results);
}

static FuncDecl *findReplacedAccessor(DeclName replacedVarName,
                                      AccessorDecl *replacement,
                                      DynamicReplacementAttr *attr,
                                      TypeChecker &TC) {

  // Retrieve the replaced abstract storage decl.
  SmallVector<ValueDecl *, 4> results;
  lookupReplacedDecl(replacedVarName, attr, replacement, results);

  if (results.empty()) {
    TC.diagnose(attr->getLocation(),
                diag::dynamic_replacement_accessor_not_found, replacedVarName);
    attr->setInvalid();
    return nullptr;
  }
  assert(results.size() == 1 && "Should only have on var or fun");

  assert(!isa<FuncDecl>(results[0]));
  TC.validateDecl(results[0]);
  auto *origStorage = cast<AbstractStorageDecl>(results[0]);
  if (!origStorage->isDynamic()) {
    TC.diagnose(attr->getLocation(),
                diag::dynamic_replacement_accessor_not_dynamic,
                replacedVarName);
    attr->setInvalid();
    return nullptr;
  }

  // Find the accessor in the replaced storage decl.
  for (auto *origAccessor : origStorage->getAllAccessors()) {
    TC.validateDecl(origAccessor);
    if (origAccessor->getAccessorKind() != replacement->getAccessorKind())
      continue;

    if (!replacement->getInterfaceType()->getCanonicalType()->matches(
            origAccessor->getInterfaceType()->getCanonicalType(),
            TypeMatchFlags::AllowABICompatible)) {
      TC.diagnose(attr->getLocation(),
                  diag::dynamic_replacement_accessor_type_mismatch,
                  replacedVarName);
      attr->setInvalid();
      return nullptr;
    }
    if (origAccessor->isImplicit() &&
        !(origStorage->getReadImpl() == ReadImplKind::Stored &&
          origStorage->getWriteImpl() == WriteImplKind::Stored)) {
      TC.diagnose(attr->getLocation(),
                  diag::dynamic_replacement_accessor_not_explicit,
                  (unsigned)origAccessor->getAccessorKind(), replacedVarName);
      attr->setInvalid();
      return nullptr;
    }
    return origAccessor;
  }
  return nullptr;
}

static AbstractFunctionDecl *
findReplacedFunction(DeclName replacedFunctionName,
                     AbstractFunctionDecl *replacement,
                     DynamicReplacementAttr *attr, TypeChecker &TC) {

  SmallVector<ValueDecl *, 4> results;
  lookupReplacedDecl(replacedFunctionName, attr, replacement, results);

  for (auto *result : results) {
    TC.validateDecl(result);
    if (result->getInterfaceType()->getCanonicalType()->matches(
            replacement->getInterfaceType()->getCanonicalType(),
            TypeMatchFlags::AllowABICompatible)) {
      if (!result->isDynamic()) {
        TC.diagnose(attr->getLocation(),
                    diag::dynamic_replacement_function_not_dynamic,
                    replacedFunctionName);
        attr->setInvalid();
        return nullptr;
      }
      return cast<AbstractFunctionDecl>(result);
    }
  }
  if (results.empty())
    TC.diagnose(attr->getLocation(),
                diag::dynamic_replacement_function_not_found,
                attr->getReplacedFunctionName());
  else {
    TC.diagnose(attr->getLocation(),
                diag::dynamic_replacement_function_of_type_not_found,
                attr->getReplacedFunctionName(),
                replacement->getInterfaceType()->getCanonicalType());

    for (auto *result : results) {
      TC.diagnose(SourceLoc(), diag::dynamic_replacement_found_function_of_type,
                  attr->getReplacedFunctionName(),
                  result->getInterfaceType()->getCanonicalType());
    }
  }
  attr->setInvalid();
  return nullptr;
}

void TypeChecker::checkDynamicReplacementAttribute(ValueDecl *D) {
  assert(isa<AbstractFunctionDecl>(D) || isa<AbstractStorageDecl>(D));

  auto *attr = D->getAttrs().getAttribute<DynamicReplacementAttr>();
  assert(attr);

  if (!isa<ExtensionDecl>(D->getDeclContext()) &&
      !D->getDeclContext()->isModuleScopeContext()) {
    diagnose(attr->getLocation(), diag::dynamic_replacement_not_in_extension,
             D->getBaseName());
    attr->setInvalid();
    return;
  }

  if (D->isNativeDynamic()) {
    diagnose(attr->getLocation(), diag::dynamic_replacement_must_not_be_dynamic,
             D->getBaseName());
    attr->setInvalid();
    return;
  }

  // Don't process a declaration twice. This will happen to accessor decls after
  // we have processed their var decls.
  if (attr->getReplacedFunction())
    return;

  SmallVector<AbstractFunctionDecl *, 4> replacements;
  SmallVector<AbstractFunctionDecl *, 4> origs;

  // Collect the accessor replacement mapping if this is an abstract storage.
  if (auto *var = dyn_cast<AbstractStorageDecl>(D)) {
     for (auto *accessor : var->getAllAccessors()) {
       validateDecl(accessor);
       if (accessor->isImplicit())
         continue;
       auto *orig = findReplacedAccessor(attr->getReplacedFunctionName(),
                                         accessor, attr, *this);
       if (attr->isInvalid())
         return;
       if (!orig)
         continue;
       origs.push_back(orig);
       replacements.push_back(accessor);
     }
  } else {
    // Otherwise, find the matching function.
    auto *fun = cast<AbstractFunctionDecl>(D);
    if (auto *orig = findReplacedFunction(attr->getReplacedFunctionName(), fun,
                                          attr, *this)) {
      origs.push_back(orig);
      replacements.push_back(fun);
    } else
      return;
  }

  // Annotate the replacement with the original func decl.
  for (auto index : indices(replacements)) {
    if (auto *attr = replacements[index]
                         ->getAttrs()
                         .getAttribute<DynamicReplacementAttr>()) {
      attr->setReplacedFunction(origs[index]);
      continue;
    }
    auto *newAttr = DynamicReplacementAttr::create(
        D->getASTContext(), attr->getReplacedFunctionName(), origs[index]);
    DeclAttributes &attrs = replacements[index]->getAttrs();
    attrs.add(newAttr);
  }

  // Remove the attribute on the abstract storage (we have moved it to the
  // accessor decl).
  if (!isa<AbstractStorageDecl>(D))
    return;
  D->getAttrs().removeAttribute(attr);
}

void AttributeChecker::visitImplementsAttr(ImplementsAttr *attr) {
  TypeLoc &ProtoTypeLoc = attr->getProtocolType();
  TypeResolutionOptions options = None;
  options |= TypeResolutionFlags::AllowUnboundGenerics;

  DeclContext *DC = D->getDeclContext();
  auto resolution = TypeResolution::forContextual(DC);
  Type T = resolution.resolveType(ProtoTypeLoc.getTypeRepr(), options);
  ProtoTypeLoc.setType(T);

  // Definite error-types were already diagnosed in resolveType.
  if (!T || T->hasError())
    return;

  // Check that we got a ProtocolType.
  if (auto PT = T->getAs<ProtocolType>()) {
    ProtocolDecl *PD = PT->getDecl();

    // Check that the ProtocolType has the specified member.
    LookupResult R = TC.lookupMember(PD->getDeclContext(),
                                     PT, attr->getMemberName());
    if (!R) {
      TC.diagnose(attr->getLocation(),
                  diag::implements_attr_protocol_lacks_member,
                  PD->getBaseName(), attr->getMemberName())
        .highlight(attr->getMemberNameLoc().getSourceRange());
    }

    // Check that the decl we're decorating is a member of a type that actually
    // conforms to the specified protocol.
    NominalTypeDecl *NTD = DC->getSelfNominalTypeDecl();
    SmallVector<ProtocolConformance *, 2> conformances;
    if (!NTD->lookupConformance(DC->getParentModule(), PD, conformances)) {
      TC.diagnose(attr->getLocation(),
                  diag::implements_attr_protocol_not_conformed_to,
                  NTD->getFullName(), PD->getFullName())
        .highlight(ProtoTypeLoc.getTypeRepr()->getSourceRange());
    }

  } else {
    TC.diagnose(attr->getLocation(),
                diag::implements_attr_non_protocol_type)
      .highlight(ProtoTypeLoc.getTypeRepr()->getSourceRange());
  }
}

void AttributeChecker::visitFrozenAttr(FrozenAttr *attr) {
  auto *ED = cast<EnumDecl>(D);

  switch (ED->getModuleContext()->getResilienceStrategy()) {
  case ResilienceStrategy::Default:
    diagnoseAndRemoveAttr(attr, diag::enum_frozen_nonresilient, attr);
    return;
  case ResilienceStrategy::Resilient:
    break;
  }

  if (ED->getFormalAccess() < AccessLevel::Public &&
      !ED->getAttrs().hasAttribute<UsableFromInlineAttr>()) {
    diagnoseAndRemoveAttr(attr, diag::enum_frozen_nonpublic, attr);
  }
}

void AttributeChecker::visitNonOverrideAttr(NonOverrideAttr *attr) {
  if (auto overrideAttr = D->getAttrs().getAttribute<OverrideAttr>()) {
    diagnoseAndRemoveAttr(overrideAttr, diag::nonoverride_and_override_attr);
  }
}

// SWIFT_ENABLE_TENSORFLOW
/// Returns true if the given type conforms to `Differentiable` in the given
/// module.
static bool conformsToDifferentiableInModule(Type type, ModuleDecl *module) {
  auto &ctx = module->getASTContext();
  auto *differentiableProto =
      ctx.getProtocol(KnownProtocolKind::Differentiable);
  return LookUpConformanceInModule(module)(
      differentiableProto->getDeclaredInterfaceType()->getCanonicalType(),
      type, differentiableProto).hasValue();
};

// SWIFT_ENABLE_TENSORFLOW
static FuncDecl *resolveAutoDiffAssociatedFunction(
    TypeChecker &TC, DeclNameWithLoc specifier, AbstractFunctionDecl *original,
    Type expectedTy, std::function<bool(FuncDecl *)> isValid) {
  auto nameLoc = specifier.Loc.getBaseNameLoc();
  auto overloadDiagnostic = [&]() {
    TC.diagnose(nameLoc, diag::differentiable_attr_overload_not_found,
                specifier.Name, expectedTy);
  };
  auto ambiguousDiagnostic = [&]() {
    TC.diagnose(nameLoc,
                diag::differentiable_attr_ambiguous_function_identifier,
                specifier.Name);
  };
  auto notFunctionDiagnostic = [&]() {
    TC.diagnose(nameLoc, diag::differentiable_attr_specified_not_function,
                specifier.Name);
  };
  std::function<void()> invalidTypeContextDiagnostic = [&]() {
    TC.diagnose(nameLoc,
                diag::differentiable_attr_function_not_same_type_context,
                specifier.Name);
  };

  // Returns true if the original function and associated function candidate
  // are defined in compatible type contexts. If the original function and the
  // associated function have different parents, or if they both have no type
  // context and are in different modules, return false.
  std::function<bool(FuncDecl *)> hasValidTypeContext = [&](FuncDecl *func) {
    // Check if both functions are top-level.
    if (!original->getInnermostTypeContext() &&
        !func->getInnermostTypeContext() &&
        original->getParentModule() == func->getParentModule())
      return true;
    // Check if both functions are defined in the same type context.
    if (auto typeCtx1 = original->getInnermostTypeContext())
      if (auto typeCtx2 = func->getInnermostTypeContext())
        return typeCtx1->getSelfNominalTypeDecl() ==
            typeCtx2->getSelfNominalTypeDecl();
    return original->getParent() == func->getParent();
  };

  auto isABIPublic = [&](AbstractFunctionDecl *func) {
    return func->getFormalAccess() >= AccessLevel::Public ||
           func->getAttrs().hasAttribute<InlinableAttr>() ||
           func->getAttrs().hasAttribute<UsableFromInlineAttr>();
  };

  // If the original function is exported (i.e. it is public or
  // @usableFromInline), then the associated functions must also be exported.
  // Returns true on error.
  auto checkAccessControl = [&](FuncDecl *func) {
    if (!isABIPublic(original))
      return false;
    if (isABIPublic(func))
      return false;
    TC.diagnose(nameLoc, diag::differentiable_attr_invalid_access,
                specifier.Name, original->getFullName());
    return true;
  };

  auto originalTypeCtx = original->getInnermostTypeContext();
  if (!originalTypeCtx) originalTypeCtx = original->getParent();
  assert(originalTypeCtx);

  // Set lookup options.
  auto lookupOptions = defaultMemberLookupOptions
      | NameLookupFlags::IgnoreAccessControl;

  auto candidate = TC.lookupFuncDecl(
      specifier.Name, nameLoc, /*baseType*/ Type(), originalTypeCtx, isValid,
      overloadDiagnostic, ambiguousDiagnostic, notFunctionDiagnostic,
      lookupOptions, hasValidTypeContext, invalidTypeContextDiagnostic);

  if (!candidate)
    return nullptr;

  if (checkAccessControl(candidate))
    return nullptr;

  return candidate;
}

// SWIFT_ENABLE_TENSORFLOW
// Checks that the `candidate` function type equals the `required` function
// type. Parameter labels are not checked.
// `checkGenericSignature` is used to check generic signatures, if specified.
// Otherwise, generic signatures are checked for equality.
static bool checkFunctionSignature(
    CanAnyFunctionType required, CanType candidate,
    Optional<std::function<bool(GenericSignature *, GenericSignature *)>>
        checkGenericSignature = None) {
  // Check that candidate is actually a function.
  CanAnyFunctionType candidateFnTy = dyn_cast<AnyFunctionType>(candidate);
  if (!candidateFnTy)
    return false;

  // Check that generic signatures match.
  auto requiredGenSig = required.getOptGenericSignature();
  auto candidateGenSig = candidateFnTy.getOptGenericSignature();
  // Call generic signature check function, if specified.
  // Otherwise, check that generic signatures are equal.
  if (!checkGenericSignature) {
    if (candidateGenSig != requiredGenSig)
      return false;
  } else if (!(*checkGenericSignature)(requiredGenSig, candidateGenSig)) {
    return false;
  }

  // Check that parameters match.
  if (candidateFnTy.getParams().size() != required.getParams().size())
    return false;
  for (auto paramPair : llvm::zip(candidateFnTy.getParams(),
                                  required.getParams())) {
    // Check parameter types.
    if (!std::get<0>(paramPair).getParameterType()->isEqual(
            std::get<1>(paramPair).getParameterType()))
      return false;
  }

  // If required result type is non-function, check that result types match
  // exactly.
  CanAnyFunctionType requiredResultFnTy =
      dyn_cast<AnyFunctionType>(required.getResult());
  if (!requiredResultFnTy)
    return required.getResult()->eraseDynamicSelfType()->isEqual(
        candidateFnTy.getResult()->eraseDynamicSelfType());

  // Required result type is a function. Recurse.
  return checkFunctionSignature(requiredResultFnTy, candidateFnTy.getResult());
};

// SWIFT_ENABLE_TENSORFLOW
void AttributeChecker::visitDifferentiableAttr(DifferentiableAttr *attr) {
  auto &ctx = TC.Context;
  auto lookupConformance =
      LookUpConformanceInModule(D->getDeclContext()->getParentModule());

  AbstractFunctionDecl *original = nullptr;
  if (auto *vd = dyn_cast<VarDecl>(D)) {
    // When used on a storage decl, @differentiable refers to its getter.
    original = vd->getGetter();
  } else if (auto *afd = dyn_cast<AbstractFunctionDecl>(D)) {
    original = afd;
    if (auto *accessor = dyn_cast<AccessorDecl>(afd)) {
      // We do not support setters yet because inout is not supported yet.
      if (accessor->isSetter())
        original = nullptr;
    }
  }

  // Global immutable vars, for example, have no getter, and therefore trigger
  // this.
  if (!original) {
    diagnoseAndRemoveAttr(attr, diag::invalid_decl_attribute, attr);
    return;
  }

  // Class members are not supported by differentiation yet.
  if (original->getInnermostTypeContext() &&
      isa<ClassDecl>(original->getInnermostTypeContext())) {
    diagnoseAndRemoveAttr(attr, diag::differentiable_attr_class_unsupported);
    return;
  }

  TC.resolveDeclSignature(original);
  auto *originalFnTy = original->getInterfaceType()->eraseDynamicSelfType()
      ->castTo<AnyFunctionType>();
  auto isInstanceMethod = original->isInstanceMember();

  // If the original function has no parameters or returns the empty tuple
  // type, there's nothing to differentiate from or with-respect-to.
  auto &originalParams = *original->getParameters();
  if (!isInstanceMethod && originalParams.size() == 0) {
    TC.diagnose(attr->getLocation(), diag::differentiable_attr_no_parameters,
                original->getFullName())
        .highlight(original->getSourceRange());
    attr->setInvalid();
    return;
  }
  auto originalResultTy = originalFnTy->getResult();
  if (originalResultTy->isEqual(ctx.TheEmptyTupleType)) {
    TC.diagnose(attr->getLocation(), diag::differentiable_attr_void_result,
                original->getFullName())
        .highlight(original->getSourceRange());
    attr->setInvalid();
    return;
  }

  auto originalParamTypes = map<SmallVector<TupleTypeElt, 8>>(
      originalParams.getArray(),
      [&](ParamDecl *decl) { return decl->getInterfaceType(); });

  // Start type-checking the arguments of the @differentiable attribute. This
  // covers 'wrt:', 'jvp:', and 'vjp:', all of which are optional.

  // Handle 'where' clause, if it exists.
  // - Resolve attribute where clause requirements and store in the attribute
  //   for serialization.
  // - Compute generic signature for autodiff associated functions based on
  //   the original function's generate signature and the attribute's where
  //   clause requirements.
  GenericSignature *whereClauseGenSig = nullptr;
  GenericEnvironment *whereClauseGenEnv = nullptr;
  if (auto whereClause = attr->getWhereClause()) {
    if (whereClause->getRequirements().empty()) {
      // Where clause must not be empty.
      TC.diagnose(attr->getLocation(),
                  diag::differentiable_attr_empty_where_clause);
      attr->setInvalid();
      return;
    }

    auto *originalGenSig = original->getGenericSignature();
    if (!originalGenSig) {
      // Attributes with where clauses can only be declared on
      // generic functions.
      TC.diagnose(attr->getLocation(),
                  diag::differentiable_attr_nongeneric_trailing_where,
                  original->getFullName())
        .highlight(whereClause->getSourceRange());
      attr->setInvalid();
      return;
    }

    // Build a new generic signature for autodiff associated functions.
    GenericSignatureBuilder builder(ctx);
    // Add the original function's generic signature.
    builder.addGenericSignature(originalGenSig);

    using FloatingRequirementSource =
        GenericSignatureBuilder::FloatingRequirementSource;

    RequirementRequest::visitRequirements(
      WhereClauseOwner(original, attr), TypeResolutionStage::Structural,
      [&](const Requirement &req, RequirementRepr *reqRepr) {
        switch (req.getKind()) {
        case RequirementKind::SameType:
        case RequirementKind::Superclass:
        case RequirementKind::Conformance:
          break;

        // Layout requirements are not supported.
        case RequirementKind::Layout:
          TC.diagnose(attr->getLocation(),
                      diag::differentiable_attr_unsupported_req_kind)
            .highlight(reqRepr->getSourceRange());
          return false;
        }

        // Add requirement to generic signature builder.
        builder.addRequirement(req, reqRepr,
                               FloatingRequirementSource::forExplicit(reqRepr),
                               nullptr, original->getModuleContext());
        return false;
      });

    // Compute generic signature and environment for autodiff associated
    // functions.
    whereClauseGenSig = std::move(builder).computeGenericSignature(
        attr->getLocation(), /*allowConcreteGenericParams=*/true);
    whereClauseGenEnv = whereClauseGenSig->createGenericEnvironment();
    // Store the resolved requirements in the attribute.
    attr->setRequirements(ctx, whereClauseGenSig->getRequirements());
  }

  // Validate the 'wrt:' parameters.
  bool isMethod = original->hasImplicitSelfDecl();

  // Get the parsed wrt param indices, which have not yet been checked.
  // This is defined for parsed attributes.
  auto parsedWrtParams = attr->getParsedParameters();
  // Get checked wrt param indices.
  // This is defined only for compiler-synthesized attributes.
  AutoDiffParameterIndices *checkedWrtParamIndices =
      attr->getParameterIndices();

  // Returns true if a type conforms to `Differentiable`.
  auto conformsToDifferentiable = [&](Type type) {
    return conformsToDifferentiableInModule(
        type, original->getModuleContext());
  };

  // If checked wrt param indices are not specified, compute them using parsed
  // wrt param indices.
  if (!checkedWrtParamIndices) {
    AutoDiffParameterIndicesBuilder autoDiffParameterIndicesBuilder(
        originalFnTy);
    if (parsedWrtParams.empty()) {
      SmallVector<Type, 4> allWrtParamTypes;

      // Returns true if the i-th parameter type is differentiable.
      auto isDifferentiableParam = [&](unsigned i) {
        if (i >= allWrtParamTypes.size())
          return false;
        auto wrtParamType = original->mapTypeIntoContext(allWrtParamTypes[i]);
        // Return false for class/existential types.
        if (wrtParamType->isAnyClassReferenceType() ||
            wrtParamType->isExistentialType())
          return false;
        // Return false for function types.
        if (wrtParamType->is<AnyFunctionType>())
          return false;
        if (whereClauseGenEnv) {
          auto wrtParamInterfaceType = !wrtParamType->hasTypeParameter()
                                           ? wrtParamType->mapTypeOutOfContext()
                                           : wrtParamType;
          wrtParamType =
              whereClauseGenEnv->mapTypeIntoContext(wrtParamInterfaceType);
        }
        // Return true if the type conforms to `Differentiable`.
        return conformsToDifferentiable(wrtParamType);
      };

      // The wrt types listed when verifying are in (T1) -> (T2, T3) -> R order,
      // but the bits are in T2, T3, T1 order.
      //
      // That works out to three cases:
      // Static function on a type:
      // Check: (T2, T3).
      //
      // Method function:
      // Check: (T2, T3, T1).
      //
      // Free standing function: (This will be: (T1, T2, T3) -> R)
      // Check (T1, T2, T3).
      // TODO: Clean all this up.
      bool isStaticSelf =
          original->isStatic() || isa<ConstructorDecl>(original);
      if (auto *fnTy = originalResultTy->getAs<AnyFunctionType>()) {
        if ((!isInstanceMethod && !isStaticSelf) ||
            fnTy->getResult()->is<AnyFunctionType>()) {
          TC.diagnose(attr->getLocation(),
                      diag::differentiable_attr_no_currying);
          return;
        }
        for (auto &param : fnTy->getParams())
          allWrtParamTypes.push_back(param.getPlainType());
        assert(originalFnTy->getNumParams() == 1 &&
               "This must be in the form (Self) -> (Args...) -> R");
      }

      if (isStaticSelf) {
        auto *methodTy = originalResultTy->castTo<AnyFunctionType>();
        for (unsigned i : range(methodTy->getNumParams()))
          if (isDifferentiableParam(i))
            autoDiffParameterIndicesBuilder.setParameter(i);
      } else {
        for (auto &param : originalFnTy->getParams())
          allWrtParamTypes.push_back(param.getPlainType());

        for (unsigned i : range(autoDiffParameterIndicesBuilder.size()))
          if (isDifferentiableParam(i))
            autoDiffParameterIndicesBuilder.setParameter(i);
      }
    } else {
      // 'wrt:' is specified. Validate and collect the selected parameters.
      int lastIndex = -1;
      for (unsigned i : indices(parsedWrtParams)) {
        auto paramLoc = parsedWrtParams[i].getLoc();
        switch (parsedWrtParams[i].getKind()) {
        case ParsedAutoDiffParameter::Kind::Named: {
          auto nameIter =
              llvm::find_if(originalParams.getArray(), [&](ParamDecl *param) {
                return param->getName() == parsedWrtParams[i].getName();
              });
          // Parameter name must exist.
          if (nameIter == originalParams.end()) {
            TC.diagnose(paramLoc, diag::differentiable_attr_wrt_name_unknown,
                        parsedWrtParams[i].getName());
            return;
          }
          // Parameter names must be specified in the original order.
          unsigned index = std::distance(originalParams.begin(), nameIter);
          if ((int)index <= lastIndex) {
            TC.diagnose(paramLoc,
                        diag::differentiable_attr_wrt_names_not_original_order);
            return;
          }
          autoDiffParameterIndicesBuilder.setParameter(index);
          lastIndex = index;
          break;
        }
        case ParsedAutoDiffParameter::Kind::Self: {
          // 'self' is only applicable to instance methods.
          if (!isInstanceMethod) {
            TC.diagnose(
                paramLoc,
                diag::differentiable_attr_wrt_self_instance_method_only);
            return;
          }
          // 'self' can only be the first in the list.
          if (i > 0) {
            TC.diagnose(paramLoc,
                        diag::differentiable_attr_wrt_self_must_be_first);
            return;
          }
          autoDiffParameterIndicesBuilder.setParameter(
              autoDiffParameterIndicesBuilder.size() - 1);
          break;
        }
        }
      }
    }
    checkedWrtParamIndices = autoDiffParameterIndicesBuilder.build(ctx);
  }

  auto insertion =
      ctx.DifferentiableAttrs.try_emplace({D, checkedWrtParamIndices}, attr);
  // Differentiable attributes are uniqued by their parameter indices.
  // Reject duplicate attributes for the same decl and parameter indices pair.
  if (!insertion.second && insertion.first->getSecond() != attr) {
    diagnoseAndRemoveAttr(attr, diag::differentiable_attr_duplicate);
    return;
  }

  // This can happen when someone puts the attribute on an instance method with
  // no parameters (other than the self parameter), and does not specify a wrt
  // list.
  if (checkedWrtParamIndices->isEmpty()) {
    TC.diagnose(attr->getLocation(), diag::differentiable_attr_wrt_nothing,
                original->getFullName())
        .highlight(original->getSourceRange());
    attr->setInvalid();
    return;
  }

  // Check that the user has only selected wrt params with allowed types.
  SmallVector<Type, 4> wrtParamTypes;
  checkedWrtParamIndices->getSubsetParameterTypes(originalFnTy, wrtParamTypes);
  for (unsigned i : range(wrtParamTypes.size())) {
    auto wrtParamType = original->mapTypeIntoContext(wrtParamTypes[i]);
    SourceLoc loc = parsedWrtParams.empty()
        ? attr->getLocation()
        : parsedWrtParams[i].getLoc();
    if (wrtParamType->isAnyClassReferenceType() ||
        wrtParamType->isExistentialType()) {
      TC.diagnose(
          loc,
          diag::differentiable_attr_cannot_diff_wrt_objects_or_existentials,
          wrtParamType);
      attr->setInvalid();
      return;
    }
    if (wrtParamType->is<AnyFunctionType>()) {
      TC.diagnose(loc, diag::differentiable_attr_cannot_diff_wrt_functions,
                  wrtParamType);
      attr->setInvalid();
      return;
    }

    // We also require that all the wrt params have associated tangent/cotangent
    // spaces.
    if (whereClauseGenEnv) {
      auto wrtParamInterfaceType = !wrtParamType->hasTypeParameter() ?
          wrtParamType->mapTypeOutOfContext() :
          wrtParamType;
      wrtParamType =
          whereClauseGenEnv->mapTypeIntoContext(wrtParamInterfaceType);
    }
    if (!conformsToDifferentiable(wrtParamType)) {
      TC.diagnose(loc, diag::differentiable_attr_wrt_not_differentiable,
                  wrtParamType);
      attr->setInvalid();
      return;
    }
  }

  // Check that all the result types have associated tangent/cotangent spaces.
  {
    auto *unwrapped = originalFnTy;
    if (isMethod)
      unwrapped = unwrapped->getResult()->castTo<AnyFunctionType>();
    Type originalResult = unwrapped->getResult();
    if (auto *resultTuple = originalResult->getAs<TupleType>()) {
      for (unsigned i : range(resultTuple->getNumElements())) {
        auto &resultTupleElt = resultTuple->getElement(i);
        auto resultTupleEltType = resultTupleElt.getType();
        if (whereClauseGenEnv) {
          resultTupleEltType = whereClauseGenEnv->mapTypeIntoContext(
              resultTupleEltType->mapTypeOutOfContext());
        }
        if (!conformsToDifferentiable(resultTupleEltType)) {
          TC.diagnose(attr->getLocation(),
                      diag::differentiable_attr_result_not_differentiable,
                      resultTupleElt.getType());
          attr->setInvalid();
          return;
        }
      }
    } else {
      if (whereClauseGenEnv) {
        auto originalResultInterfaceType = !originalResult->hasTypeParameter()
            ? originalResult->mapTypeOutOfContext()
            : originalResult;
        originalResult =
            whereClauseGenEnv->mapTypeIntoContext(originalResultInterfaceType);
      }
      if (!conformsToDifferentiable(originalResult)) {
        TC.diagnose(attr->getLocation(),
                    diag::differentiable_attr_result_not_differentiable,
                    originalResult);
        attr->setInvalid();
        return;
      }
    }
  }

  // Memorize the checked parameter indices in the attribute.
  attr->setParameterIndices(checkedWrtParamIndices);

  // Checks that the `candidate` function type equals the `required` function
  // type, disregarding parameter labels.
  //
  // Precondition: `required` has no parameter labels.
  std::function<bool(CanAnyFunctionType, CanType)> checkFunctionSignature;
  checkFunctionSignature = [&](CanAnyFunctionType required,
                               CanType candidate) -> bool {

    // Check that candidate is actually a function.
    CanAnyFunctionType candidateFnTy = dyn_cast<AnyFunctionType>(candidate);
    if (!candidateFnTy)
      return false;

    // Check that generic signatures match.
    if (candidateFnTy.getOptGenericSignature() !=
        required.getOptGenericSignature())
      return false;

    // Check that parameter types match (disregards labels).
    if (candidateFnTy.getParams().size() != required.getParams().size())
      return false;
    for (auto paramPair : llvm::zip(candidateFnTy.getParams(),
                                    required.getParams()))
      if (!std::get<0>(paramPair).getPlainType()->isEqual(
          std::get<1>(paramPair).getPlainType()))
        return false;

    // If required result type is non-function, check that result types match
    // exactly.
    CanAnyFunctionType requiredResultFnTy =
        dyn_cast<AnyFunctionType>(required.getResult());
    if (!requiredResultFnTy)
      return required.getResult() == candidateFnTy.getResult();

    // Required result type is a function. Recurse.
    return checkFunctionSignature(requiredResultFnTy,
                                  candidateFnTy.getResult());
  };

  // Resolve the JVP declaration, if it exists.
  if (attr->getJVP()) {
    AnyFunctionType *expectedJVPFnTy =
        originalFnTy->getAutoDiffAssociatedFunctionType(
            checkedWrtParamIndices, /*resultIndex*/ 0,
            /*differentiationOrder*/ 1, AutoDiffAssociatedFunctionKind::JVP,
            lookupConformance, whereClauseGenSig);

    auto isValidJVP = [&](FuncDecl *jvpCandidate) {
      TC.validateDeclForNameLookup(jvpCandidate);
      return checkFunctionSignature(
          cast<AnyFunctionType>(expectedJVPFnTy->getCanonicalType()),
          jvpCandidate->getInterfaceType()->getCanonicalType());
    };

    FuncDecl *jvp = resolveAutoDiffAssociatedFunction(
        TC, attr->getJVP().getValue(), original, expectedJVPFnTy, isValidJVP);

    if (!jvp) {
      attr->setInvalid();
      return;
    }
    // Memorize the jvp reference in the attribute.
    attr->setJVPFunction(jvp);
  }

  // Resolve the VJP declaration, if it exists.
  if (attr->getVJP()) {
    AnyFunctionType *expectedVJPFnTy =
        originalFnTy->getAutoDiffAssociatedFunctionType(
            checkedWrtParamIndices, /*resultIndex*/ 0,
            /*differentiationOrder*/ 1, AutoDiffAssociatedFunctionKind::VJP,
            lookupConformance, whereClauseGenSig);

    auto isValidVJP = [&](FuncDecl *vjpCandidate) {
      TC.validateDeclForNameLookup(vjpCandidate);
      return checkFunctionSignature(
          cast<AnyFunctionType>(expectedVJPFnTy->getCanonicalType()),
          vjpCandidate->getInterfaceType()->getCanonicalType());
    };

    FuncDecl *vjp = resolveAutoDiffAssociatedFunction(
        TC, attr->getVJP().getValue(), original, expectedVJPFnTy, isValidVJP);

    if (!vjp) {
      attr->setInvalid();
      return;
    }
    // Memorize the vjp reference in the attribute.
    attr->setVJPFunction(vjp);
  }
}

// SWIFT_ENABLE_TENSORFLOW
// Makes a function with the same generic signature and extinfo as `copy`, but
// with `params` parameters and `retTy` return type.
static AnyFunctionType *
makeFunctionType(AnyFunctionType *copy, ArrayRef<AnyFunctionType::Param> params,
                 Type retTy, GenericSignature *genericSignature) {
  if (!genericSignature)
    if (auto *genericFunctionType = copy->getAs<GenericFunctionType>())
      genericSignature = genericFunctionType->getGenericSignature();
  if (genericSignature)
    return GenericFunctionType::get(genericSignature, params, retTy,
                                    copy->getExtInfo());
  return FunctionType::get(params, retTy, copy->getExtInfo());
}

// SWIFT_ENABLE_TENSORFLOW
// Return the original function type corresponding to the given derivative
// function type.
static AnyFunctionType *
getAutoDiffOriginalFunctionType(AnyFunctionType *derivativeType) {
  // Unwrap curry levels.
  SmallVector<AnyFunctionType *, 2> curryLevels;
  auto *currentLevel = derivativeType;
  while (currentLevel != nullptr) {
    curryLevels.push_back(currentLevel);
    currentLevel = currentLevel->getResult()->getAs<AnyFunctionType>();
  }

  auto derivativeResult = curryLevels.back()->getResult()->getAs<TupleType>();
  assert(derivativeResult && derivativeResult->getNumElements() == 2 &&
         "Expected derivative result to be a two-element tuple");
  auto originalResult = derivativeResult->getElement(0).getType();
  auto genericSignature = derivativeType->getOptGenericSignature();
  auto *originalType = makeFunctionType(
      curryLevels.back(), curryLevels.back()->getParams(), originalResult,
      curryLevels.size() == 1 ? genericSignature : nullptr);

  // Wrap the associated function type in additional curry levels.
  auto curryLevelsWithoutLast =
      ArrayRef<AnyFunctionType *>(curryLevels).drop_back(1);
  for (auto pair : enumerate(reversed(curryLevelsWithoutLast))) {
    unsigned i = pair.index();
    AnyFunctionType *curryLevel = pair.value();
    originalType = makeFunctionType(
        curryLevel, curryLevel->getParams(), originalType,
        i == curryLevelsWithoutLast.size() - 1 ? genericSignature : nullptr);
  }
  return originalType;
}

// SWIFT_ENABLE_TENSORFLOW
void AttributeChecker::visitDifferentiatingAttr(DifferentiatingAttr *attr) {
  auto &ctx = TC.Context;
  FuncDecl *derivative = dyn_cast<FuncDecl>(D);
  auto isMethod = derivative->hasImplicitSelfDecl();
  auto isInstanceMethod = derivative->isInstanceMember();
  auto lookupConformance =
      LookUpConformanceInModule(D->getDeclContext()->getParentModule());
  auto original = attr->getOriginal();

  // If the original function has no parameters or returns the empty tuple
  // type, there's nothing to differentiate from or with-respect-to.
  auto &derivativeParams = *derivative->getParameters();
  if (!isInstanceMethod && derivativeParams.size() == 0) {
    TC.diagnose(attr->getLocation(), diag::differentiable_attr_no_parameters,
                derivative->getName())
    .highlight(derivative->getSourceRange());
    attr->setInvalid();
    return;
  }
  // The result type should be a two-element tuple.
  // Either a value and pullback:
  //     (value: R, pullback: (R.CotangentVector) -> (T.CotangentVector...)
  // Or a value and differential:
  //     (value: R, differential: (T.TangentVector...) -> (R.TangentVector)
  auto derivativeResultType = derivative->getResultInterfaceType();
  auto derivativeResultTupleType = derivativeResultType->getAs<TupleType>();
  if (!derivativeResultTupleType ||
      derivativeResultTupleType->getNumElements() != 2) {
    TC.diagnose(attr->getLocation(),
                diag::differentiating_attr_expected_result_tuple);
    attr->setInvalid();
    return;
  }
  auto valueResultElt = derivativeResultTupleType->getElement(0);
  auto funcResultElt = derivativeResultTupleType->getElement(1);
  // Get derivative kind and associated function identifier.
  AutoDiffAssociatedFunctionKind kind;
  Identifier autoDiffAssocTyId;
  if (valueResultElt.getName().str() != "value") {
    TC.diagnose(attr->getLocation(),
                diag::differentiating_attr_expected_result_tuple_value_label);
    attr->setInvalid();
    return;
  }
  if (funcResultElt.getName().str() == "differential") {
    kind = AutoDiffAssociatedFunctionKind::JVP;
    autoDiffAssocTyId = ctx.Id_TangentVector;
  } else if (funcResultElt.getName().str() == "pullback") {
    kind = AutoDiffAssociatedFunctionKind::VJP;
    autoDiffAssocTyId = ctx.Id_CotangentVector;
  } else {
    TC.diagnose(attr->getLocation(),
                diag::differentiating_attr_expected_result_tuple_func_label);
    attr->setInvalid();
    return;
  }
  // `value: R` result tuple element must conform to `Differentiable`.
  auto diffableProto = ctx.getProtocol(KnownProtocolKind::__Differentiable);
  auto valueResultType = valueResultElt.getType();
  if (valueResultType->hasTypeParameter())
    valueResultType = derivative->mapTypeIntoContext(valueResultType);
  auto valueResultConf = TC.conformsToProtocol(valueResultType, diffableProto,
                                               derivative->getDeclContext(),
                                               ConformanceCheckFlags::Used);
  if (!valueResultConf) {
    TC.diagnose(attr->getLocation(),
                diag::differentiating_attr_result_value_not_differentiable,
                valueResultElt.getType());
    attr->setInvalid();
    return;
  }
  // Function tuple result must take one parameter with type either
  // `R.TangentVector` or `R.CotangentVector`.
  auto seedTy = ProtocolConformanceRef::getTypeWitnessByName(
      valueResultType, *valueResultConf, autoDiffAssocTyId,
      ctx.getLazyResolver());
  auto funcEltType = funcResultElt.getType()->getAs<AnyFunctionType>();
  if (funcEltType->hasTypeParameter())
    funcEltType = derivative->mapTypeIntoContext(
        funcResultElt.getType())->getAs<AnyFunctionType>();
  if (!funcEltType || funcEltType->getNumParams() != 1 ||
      !funcEltType->getParams().front().getPlainType()->isEqual(seedTy)) {
    TC.diagnose(attr->getLocation(),
                diag::differentiating_attr_result_func_invalid_parameter,
                funcResultElt.getName(), seedTy);
    attr->setInvalid();
    return;
  }

  // Gather inferred differentiation parameters.
  SmallVector<TupleTypeElt, 4> diffParams;
  auto addDiffParam = [&](Type paramType) {
    auto conf = TC.conformsToProtocol(paramType, diffableProto, derivative,
                                      ConformanceCheckFlags::Used);
    if (!conf)
      return;
    auto diffParamType = ProtocolConformanceRef::getTypeWitnessByName(
        paramType, *conf, autoDiffAssocTyId, ctx.getLazyResolver());
    diffParams.push_back(TupleTypeElt(diffParamType));
  };

  auto *derivativeInterfaceType =
      derivative->getInterfaceType()->castTo<AnyFunctionType>();
  auto *derivativeType = isMethod
      ? derivative->getMethodInterfaceType()->castTo<AnyFunctionType>()
      : derivativeInterfaceType;
  // If `derivative` is an instance method, check whether `Self` conforms to
  // `Differentiable`.
  if (isInstanceMethod) {
    auto selfType = derivative->getImplicitSelfDecl()->getInterfaceType();
    if (selfType->hasTypeParameter())
      selfType = derivative->getParent()->mapTypeIntoContext(selfType);
    addDiffParam(selfType);
  }
  // Check whether every parameter conforms to `Differentiable`.
  for (auto param : derivativeType->getParams()) {
    auto paramType = param.getPlainType();
    if (param.isNonDifferentiable())
      continue;
    if (paramType->hasTypeParameter())
      paramType = derivative->mapTypeIntoContext(paramType);
    addDiffParam(paramType);
  }
  // There must be at least one differentiation parameter.
  if (diffParams.empty()) {
    TC.diagnose(attr->getLocation(),
                diag::differentiating_attr_no_diff_parameters);
    attr->setInvalid();
    return;
  }

  // Check returned parameter derivatives type against expected type.
  auto expectedDiffParamsType = TupleType::get(diffParams, ctx);
  auto diffParamsType = funcEltType->getResult();
  if (!diffParamsType || !diffParamsType->isEqual(expectedDiffParamsType)) {
    TC.diagnose(attr->getLocation(),
                diag::differentiating_attr_unexpected_diff_params_type,
                diffParamsType, expectedDiffParamsType);
    attr->setInvalid();
    return;
  }

  auto *originalFnType =
      getAutoDiffOriginalFunctionType(derivativeInterfaceType);

  std::function<bool(GenericSignature *, GenericSignature *)>
    checkGenericSignatureSatisfied =
        [&](GenericSignature *source, GenericSignature *target) {
          // If target is null, then its requirements are satisfied.
          if (!target)
            return true;
          // If source is null but target is not null, then target's
          // requirements are not satisfied.
          if (!source)
            return false;
          // Check if target's requirements are satisfied by source.
          return TC.checkGenericArguments(
                     derivative, original.Loc.getBaseNameLoc(),
                     original.Loc.getBaseNameLoc(), Type(),
                     source->getGenericParams(), target->getRequirements(),
                     [](SubstitutableType *dependentType) {
                       return Type(dependentType);
                     }, lookupConformance) == RequirementCheckResult::Success;
  };

  auto isValidOriginal = [&](FuncDecl *originalCandidate) {
    TC.validateDeclForNameLookup(originalCandidate);
    return checkFunctionSignature(
        cast<AnyFunctionType>(originalFnType->getCanonicalType()),
        originalCandidate->getInterfaceType()->getCanonicalType(),
        checkGenericSignatureSatisfied);
  };

  auto overloadDiagnostic = [&]() {
    TC.diagnose(original.Loc, diag::differentiating_attr_overload_not_found,
                original.Name, originalFnType);
  };
  auto ambiguousDiagnostic = [&]() {
    TC.diagnose(original.Loc,
                diag::differentiable_attr_ambiguous_function_identifier,
                original.Name);
  };
  auto notFunctionDiagnostic = [&]() {
    TC.diagnose(original.Loc, diag::differentiable_attr_specified_not_function,
                original.Name);
  };
  std::function<void()> invalidTypeContextDiagnostic = [&]() {
    TC.diagnose(original.Loc,
                diag::differentiable_attr_function_not_same_type_context,
                original.Name);
  };

  // Returns true if the derivative function and original function candidate
  // are defined in compatible type contexts. If the derivative function and the
  // original function candidate have different parents, return false.
  std::function<bool(FuncDecl *)> hasValidTypeContext = [&](FuncDecl *func) {
    // Check if both functions are top-level.
    if (!derivative->getInnermostTypeContext() &&
        !func->getInnermostTypeContext())
      return true;
    // Check if both functions are defined in the same type context.
    if (auto typeCtx1 = derivative->getInnermostTypeContext())
      if (auto typeCtx2 = func->getInnermostTypeContext()) {
        return typeCtx1->getSelfNominalTypeDecl() ==
            typeCtx2->getSelfNominalTypeDecl();
      }
    return derivative->getParent() == func->getParent();
  };

  auto lookupOptions = defaultMemberLookupOptions
      | NameLookupFlags::IgnoreAccessControl;
  auto derivativeTypeCtx = derivative->getInnermostTypeContext();
  if (!derivativeTypeCtx) derivativeTypeCtx = derivative->getParent();
  assert(derivativeTypeCtx);

  // Look up original function.
  auto *originalFn = TC.lookupFuncDecl(
      original.Name, original.Loc.getBaseNameLoc(), /*baseType*/ Type(),
      derivativeTypeCtx, isValidOriginal, overloadDiagnostic,
      ambiguousDiagnostic, notFunctionDiagnostic, lookupOptions,
      hasValidTypeContext, invalidTypeContextDiagnostic);
  if (!originalFn) {
    attr->setInvalid();
    return;
  }
  attr->setOriginalFunction(originalFn);

  // Reject different-file retroactive derivatives.
  // TODO(TF-136): Full support for cross-file/cross-module retroactive
  // differentiability will require SIL differnetiability witnesses and lots of
  // plumbing.
  if (originalFn->getParentSourceFile() != derivative->getParentSourceFile()) {
    diagnoseAndRemoveAttr(
        attr, diag::differentiating_attr_not_in_same_file_as_original);
    return;
  }

  // TODO: When `wrt:` is supported in the `@differentiating` attribute, replace
  // this with the parameter indices resolved by the earlier checking logic in
  // this function.
  auto allParameterIndices =
      AutoDiffParameterIndicesBuilder(originalFnType, /*setAllParams*/ true)
          .build(ctx);

  // Add the derivative function to the original function's `@differentiable`
  // attribute with the same parameters. If this attribute does not exist,
  // create one.
  DifferentiableAttr *da = nullptr;
  for (auto *cda : originalFn->getAttrs().getAttributes<DifferentiableAttr>())
    if (allParameterIndices == cda->getParameterIndices())
      da = const_cast<DifferentiableAttr *>(cda);

  // TODO: Infer the original `@differentiable`'s generic requirements.
  if (!da) {
    da = DifferentiableAttr::create(ctx, /*implicit*/ true, SourceLoc(),
                                    SourceRange(), allParameterIndices, None,
                                    None, {});
    originalFn->getAttrs().add(da);
  }
  switch (kind) {
  case AutoDiffAssociatedFunctionKind::JVP:
    if (auto jvp = da->getJVP()) {
      diagnoseAndRemoveAttr(
          attr, diag::differentiating_attr_original_already_has_derivative,
          jvp->Name);
      return;
    }
    da->setJVPFunction(derivative);
    break;
  case AutoDiffAssociatedFunctionKind::VJP:
    if (auto vjp = da->getVJP()) {
      diagnoseAndRemoveAttr(
          attr, diag::differentiating_attr_original_already_has_derivative,
          vjp->Name);
      return;
    }
    da->setVJPFunction(derivative);
    break;
  }
}

static bool
compilerEvaluableAllowedInExtensionDecl(ExtensionDecl *extensionDecl) {
  auto extendedTypeKind = extensionDecl->getExtendedType()->getKind();
  return extendedTypeKind == TypeKind::Enum ||
         extendedTypeKind == TypeKind::Protocol ||
         extendedTypeKind == TypeKind::Struct ||
         extendedTypeKind == TypeKind::BoundGenericEnum ||
         extendedTypeKind == TypeKind::BoundGenericStruct;
}

void AttributeChecker::visitCompilerEvaluableAttr(CompilerEvaluableAttr *attr) {
  // Check that the function is defined in an allowed context.
  // TODO(marcrasi): In many cases, we can probably generate a more informative
  // error message than just saying that it's "not allowed here". (Like "not
  // allowed in a class [point at the class decl], put it at the top level or in
  // a struct instead").
  auto declContext = D->getDeclContext();
  switch (declContext->getContextKind()) {
  case DeclContextKind::AbstractFunctionDecl:
    // Nested functions are okay.
    break;
  case DeclContextKind::ExtensionDecl:
    // Enum, Protocol, and Struct extensions are okay. For Enums and Structs
    // extensions, the extended type must be compiler-representable.
    // TODO(marcrasi): Check that the extended type is compiler-representable.
    if (!compilerEvaluableAllowedInExtensionDecl(
            cast<ExtensionDecl>(declContext))) {
      TC.diagnose(D, diag::compiler_evaluable_bad_context);
      attr->setInvalid();
      return;
    }
    break;
  case DeclContextKind::FileUnit:
    // Top level functions are okay.
    break;
  case DeclContextKind::GenericTypeDecl:
    switch (cast<GenericTypeDecl>(declContext)->getKind()) {
    case DeclKind::Enum:
      // Enums are okay, if they are compiler-representable.
      // TODO(marcrasi): Check that it's compiler-representable.
      break;
    case DeclKind::Struct:
      // Structs are okay, if they are compiler-representable.
      // TODO(marcrasi): Check that it's compiler-representable.
      break;
    default:
      TC.diagnose(D, diag::compiler_evaluable_bad_context);
      attr->setInvalid();
      return;
    }
    break;
  default:
    TC.diagnose(D, diag::compiler_evaluable_bad_context);
    attr->setInvalid();
    return;
  }

  // Check that the signature only has allowed types.
  // TODO(marcrasi): Do this.

  // For @compilerEvaluable to be truly valid, the function body must also
  // follow certain rules. We can only check these rules after the body is type
  // checked, and it's not type checked yet, so we check these rules later in
  // TypeChecker::checkFunctionBodyCompilerEvaluable().
}

// SWIFT_ENABLE_TENSORFLOW
void AttributeChecker::visitTensorFlowGraphAttr(TensorFlowGraphAttr *attr) {
  FuncDecl *FD = cast<FuncDecl>(D);
  // The function must be top-level.
  if (FD->getImplicitSelfDecl()) {
    diagnoseAndRemoveAttr(attr, diag::tf_graph_attr_top_level_only);
    return;
  }
  // Generic functions are not supported.
  if (FD->isGeneric()) {
    diagnoseAndRemoveAttr(attr, diag::tf_graph_attr_no_generic_functions);
    return;
  }
  // Only functions taking and returning TensorFlow values are permitted.
  auto allParamsAreTFValues = llvm::all_of(FD->getParameters()->getArray(),
      [&](ParamDecl *decl) {
        return tf::isTensorFlowValueOrAggregate(decl->getInterfaceType());
      });
  if (!allParamsAreTFValues ||
      !tf::isTensorFlowValueOrAggregate(FD->getResultInterfaceType())) {
    diagnoseAndRemoveAttr(attr,
                          diag::tf_graph_attr_function_tensorflow_value_only);
    return;
  }
  // Only functions with no captures are permitted.
  TC.computeCaptures(FD);
  if (!FD->getCaptureInfo().isTrivial()) {
    diagnoseAndRemoveAttr(attr,
                          diag::tf_graph_attr_no_functions_with_captures);
    return;
  }
  // Assign @convention(tensorflow).
  AnyFunctionType *fnTy = FD->getInterfaceType()->castTo<AnyFunctionType>();
  auto *newFnTy = fnTy->withExtInfo(
    fnTy->getExtInfo().withRepresentation(
      AnyFunctionType::Representation::TensorFlow));
  FD->setInterfaceType(newFnTy);
}

// SWIFT_ENABLE_TENSORFLOW
void AttributeChecker::visitFieldwiseDifferentiableAttr(
    FieldwiseDifferentiableAttr *attr) {
  auto *structDecl = dyn_cast<StructDecl>(D);
  if (!structDecl) {
    diagnoseAndRemoveAttr(attr,
        diag::fieldwise_differentiable_only_on_differentiable_structs);
    return;
  }
  if (!conformsToDifferentiableInModule(
          structDecl->getDeclaredInterfaceType(), D->getModuleContext())) {
    diagnoseAndRemoveAttr(attr,
        diag::fieldwise_differentiable_only_on_differentiable_structs);
    return;
  }
}

// SWIFT_ENABLE_TENSORFLOW
void AttributeChecker::visitNoDerivativeAttr(NoDerivativeAttr *attr) {
  auto *vd = dyn_cast<VarDecl>(D);
  if (attr->isImplicit())
    return;
  if (!vd || vd->isStatic()) {
    diagnoseAndRemoveAttr(attr,
        diag::noderivative_only_on_stored_properties_in_differentiable_structs);
    return;
  }
  auto *structDecl = dyn_cast<StructDecl>(vd->getDeclContext());
  if (!structDecl) {
    diagnoseAndRemoveAttr(attr,
        diag::noderivative_only_on_stored_properties_in_differentiable_structs);
    return;
  }
  if (!conformsToDifferentiableInModule(
          structDecl->getDeclaredInterfaceType(), D->getModuleContext())) {
    diagnoseAndRemoveAttr(attr,
        diag::noderivative_only_on_stored_properties_in_differentiable_structs);
    return;
  }
}

void TypeChecker::checkDeclAttributes(Decl *D) {
  AttributeChecker Checker(*this, D);

  for (auto attr : D->getAttrs()) {
    if (attr->isValid())
      Checker.visit(attr);
  }
}

void TypeChecker::checkTypeModifyingDeclAttributes(VarDecl *var) {
  if (!var->hasType())
    return;

  if (auto *attr = var->getAttrs().getAttribute<ReferenceOwnershipAttr>())
    checkReferenceOwnershipAttr(var, attr);
}

void TypeChecker::checkReferenceOwnershipAttr(VarDecl *var,
                                              ReferenceOwnershipAttr *attr) {
  // Don't check ownership attribute if the declaration is already marked invalid.
  if (var->isInvalid())
    return;

  Type type = var->getType();
  Type interfaceType = var->getInterfaceType();

  // Just stop if we've already processed this declaration.
  if (type->is<ReferenceStorageType>())
    return;

  auto ownershipKind = attr->get();

  // A weak variable must have type R? or R! for some ownership-capable type R.
  auto underlyingType = type->getOptionalObjectType();
  auto isOptional = bool(underlyingType);

  switch (optionalityOf(ownershipKind)) {
  case ReferenceOwnershipOptionality::Disallowed:
    if (isOptional) {
      diagnose(var->getStartLoc(), diag::invalid_ownership_with_optional,
               ownershipKind)
        .fixItReplace(attr->getRange(), "weak");
      attr->setInvalid();
    }
    break;
  case ReferenceOwnershipOptionality::Allowed:
    if (!isOptional)
      break;
    LLVM_FALLTHROUGH;
  case ReferenceOwnershipOptionality::Required:
    if (var->isLet()) {
      diagnose(var->getStartLoc(), diag::invalid_ownership_is_let,
               ownershipKind);
      attr->setInvalid();
    }

    // While @IBOutlet can be weak, it must be optional. Let it diagnose.
    if (!isOptional && !var->getAttrs().hasAttribute<IBOutletAttr>()) {
      attr->setInvalid();
      auto diag = diagnose(var->getStartLoc(),
                           diag::invalid_ownership_not_optional,
                           ownershipKind,
                           OptionalType::get(type));
      auto typeRange = var->getTypeSourceRangeForDiagnostics();
      if (type->hasSimpleTypeRepr()) {
        diag.fixItInsertAfter(typeRange.End, "?");
      } else {
        diag.fixItInsert(typeRange.Start, "(")
          .fixItInsertAfter(typeRange.End, ")?");
      }
    }
    break;
  }

  if (!underlyingType)
    underlyingType = type;

  if (!underlyingType->allowsOwnership()) {
    auto D = diag::invalid_ownership_type;

    if (underlyingType->isExistentialType() ||
        underlyingType->is<ArchetypeType>()) {
      // Suggest the possibility of adding a class bound.
      D = diag::invalid_ownership_protocol_type;
    }

    diagnose(var->getStartLoc(), D, ownershipKind, underlyingType);
    attr->setInvalid();
  }

  auto PDC = dyn_cast<ProtocolDecl>((var->getDeclContext()));
  if (PDC && !PDC->isObjC()) {
    // Ownership does not make sense in protocols, except for "weak" on
    // properties of Objective-C protocols.
    auto D = Context.isSwiftVersionAtLeast(5)
           ? diag::ownership_invalid_in_protocols
           : diag::ownership_invalid_in_protocols_compat_warning;
    diagnose(attr->getLocation(), D, ownershipKind)
      .fixItRemove(attr->getRange());
    attr->setInvalid();
  }

  if (attr->isInvalid())
    return;

  // Change the type to the appropriate reference storage type.
  var->setType(ReferenceStorageType::get(
      type, ownershipKind, Context));
  var->setInterfaceType(ReferenceStorageType::get(
      interfaceType, ownershipKind, Context));
}

Optional<Diag<>>
TypeChecker::diagnosticIfDeclCannotBePotentiallyUnavailable(const Decl *D) {
  DeclContext *DC = D->getDeclContext();
  // Do not permit potential availability of script-mode global variables;
  // their initializer expression is not lazily evaluated, so this would
  // not be safe.
  if (isa<VarDecl>(D) && DC->isModuleScopeContext() &&
      DC->getParentSourceFile()->isScriptMode()) {
    return diag::availability_global_script_no_potential;
  }

  // For now, we don't allow stored properties to be potentially unavailable.
  // We will want to support these eventually, but we haven't figured out how
  // this will interact with Definite Initialization, deinitializers and
  // resilience yet.
  if (auto *VD = dyn_cast<VarDecl>(D)) {
    // Globals and statics are lazily initialized, so they are safe
    // for potential unavailability. Note that if D is a global in script
    // mode (which are not lazy) then we will already have returned
    // a diagnosis above.
    bool lazilyInitializedStored = VD->isStatic() ||
                                   VD->getAttrs().hasAttribute<LazyAttr>() ||
                                   DC->isModuleScopeContext();

    if (VD->hasStorage() && !lazilyInitializedStored) {
      return diag::availability_stored_property_no_potential;
    }
  }

  return None;
}

void TypeChecker::addImplicitDynamicAttribute(Decl *D) {
  if (!D->getModuleContext()->isImplicitDynamicEnabled())
    return;

  // Add the attribute if the decl kind allows it and it is not an accessor
  // decl. Accessor decls should always infer the var/subscript's attribute.
  if (!DeclAttribute::canAttributeAppearOnDecl(DAK_Dynamic, D) ||
      isa<AccessorDecl>(D))
    return;

  if (D->getAttrs().hasAttribute<FinalAttr>() ||
      D->getAttrs().hasAttribute<NonObjCAttr>() ||
      D->getAttrs().hasAttribute<TransparentAttr>() ||
      D->getAttrs().hasAttribute<InlinableAttr>())
    return;

  if (auto *VD = dyn_cast<VarDecl>(D)) {
    // Don't turn stored into computed properties. This could conflict with
    // exclusivity checking.
    if (VD->hasStorage())
      return;
    // Don't add dynamic to local variables.
    if (VD->getDeclContext()->isLocalContext())
      return;
    // Don't add to implicit variables.
    if (VD->isImplicit())
      return;
  }

  if (!D->getAttrs().hasAttribute<DynamicAttr>() &&
      !D->getAttrs().hasAttribute<DynamicReplacementAttr>()) {
    auto attr = new (D->getASTContext()) DynamicAttr(/*implicit=*/true);
    D->getAttrs().add(attr);
  }
}

/* ---------------------------------------------------------------------------
 * Error handling
 *
 * ---------------------------------------------------------------------------*/

#define SWIG_Error(code, msg)     SWIGV8_ErrorHandler.error(code, msg)
#define SWIG_exception(code, msg) SWIGV8_ErrorHandler.error(code, msg)
#define SWIG_fail                 goto fail
#define SWIGV8_OVERLOAD false

static void SWIG_V8_Raise(const char* msg) {
#if (SWIG_V8_VERSION < 0x032410)
  v8::ThrowException(v8::Exception::Error(v8::String::New(msg)));
#else
  v8::Isolate *iso = v8::Isolate::GetCurrent();
  iso->ThrowException(v8::Exception::Error(v8::String::NewFromUtf8(iso, msg)));
#endif
}

/*
  Note: There are two contexts for handling errors.
  A static V8ErrorHandler is used in not overloaded methods.
  For overloaded methods the throwing type checking mechanism is used
  during dispatching. As V8 exceptions can not be resetted properly
  the trick is to use a dynamic ErrorHandler with same local name as the global
  one.

  - See defintion of SWIG_Error above.
  - See code templates 'JS_function_dispatcher', 'JS_functionwrapper_overload',
    and 'JS_function_dispatch_case' in javascriptcode.swg

*/
class V8ErrorHandler {
public:
  virtual ~V8ErrorHandler() {}
  virtual void error(int code, const char* msg) {
    SWIG_V8_Raise(msg);
  }
};
// this is used in usually
static V8ErrorHandler SWIGV8_ErrorHandler;

// instances of this are used in overloaded functions
class OverloadErrorHandler: public V8ErrorHandler {
  int _code;
public:
  OverloadErrorHandler(): _code(0) {}
  virtual void error(int code, const char* msg) {
    _code = code;
    if(code != SWIG_TypeError) {
      V8ErrorHandler::error(code, msg);
    }
  }

  inline void clear() { _code = 0; }
  inline bool shouldReturn() const { return _code != SWIG_TypeError; }
};

// Note: these typedefs and defines are used to deal with  v8 API changes since version 3.19.00

#if (SWIG_V8_VERSION < 0x031900)
typedef v8::Handle<v8::Value> SwigV8ReturnValue;
typedef v8::Arguments SwigV8Arguments;
typedef v8::AccessorInfo SwigV8PropertyCallbackInfo;
#define SWIGV8_RETURN(val) return SWIGV8_SCOPE_CLOSE(scope, val)
#define SWIGV8_RETURN_UNDEF() return SWIGV8_SCOPE_CLOSE(scope, v8::Undefined())
#else
typedef void SwigV8ReturnValue;
typedef v8::FunctionCallbackInfo<v8::Value> SwigV8Arguments;
typedef v8::PropertyCallbackInfo<v8::Value> SwigV8PropertyCallbackInfo;
#define SWIGV8_RETURN(val) args.GetReturnValue().Set(val); return
#define SWIGV8_RETURN_UNDEF() args.GetReturnValue().SetUndefined(); return
#endif

#if (SWIG_V8_VERSION < 0x032113)
#	define SWIGV8_SCOPE(name) v8::HandleScope name
#	define SWIGV8_SCOPE_CLOSE(name, handler) name.Close(handler)
#	define SWIGV8_STRING(str) v8::String::New(str)
#	define SWIGV8_SYMBOL(sym) v8::String::NewSymbol(sym)
#	define SWIGV8_UNDEFINED v8::Undefined()
#	define SWIGV8_ISO_ARG
#elif (SWIG_V8_VERSION < 0x032410)
#	define SWIGV8_SCOPE(name) v8::Isolate *iso = v8::Isolate::GetCurrent(); v8::HandleScope name(iso)
#	define SWIGV8_SCOPE_CLOSE(name, handler) name.Close(handler)
#	define SWIGV8_STRING(str) v8::String::New(str)
#	define SWIGV8_SYMBOL(sym) v8::String::NewSymbol(sym)
#	define SWIGV8_UNDEFINED v8::Undefined()
#	define SWIGV8_ISO_ARG
#else
#	define SWIGV8_SCOPE(name) v8::Isolate *iso = v8::Isolate::GetCurrent(); v8::EscapableHandleScope name(iso)
#	define SWIGV8_SCOPE_CLOSE(name, handler) name.Escape(handler)
#	define SWIGV8_STRING(str) v8::String::NewFromUtf8(iso, str)
#	define SWIGV8_SYMBOL(sym) v8::String::NewFromUtf8(iso, sym, v8::String::kInternalizedString)
#	define SWIGV8_UNDEFINED v8::Undefined(iso)
#	define SWIGV8_ISO_ARG iso,
#endif


/* ---------------------------------------------------------------------------
 * Basic Proxy object
 *
 * ---------------------------------------------------------------------------*/

class SWIGV8_Proxy {
public:
  SWIGV8_Proxy(): swigCMemOwn(false), swigCObject(0), info(0) {};

  ~SWIGV8_Proxy() {
#if (SWIG_V8_VERSION < 0x031900 || (SWIG_V8_VERSION >= 0x032100 && SWIG_V8_VERSION < 0x032410))
    handle.ClearWeak();
    handle.Dispose();
    handle.Clear();
#elif (SWIG_V8_VERSION < 0x032410)
    handle.ClearWeak(v8::Isolate::GetCurrent());
    handle.Dispose(v8::Isolate::GetCurrent());
    handle.Clear();
#else
    handle.ClearWeak();
    /* persistent dtor now */
#endif
  }

  bool swigCMemOwn;
  void *swigCObject;
  swig_type_info *info;
  v8::Persistent<v8::Object> handle;
};

class SWIGV8_ClientData {
public:
  v8::Persistent<v8::FunctionTemplate> class_templ;

#if (SWIG_V8_VERSION < 0x031900)
  void (*dtor) (v8::Persistent< v8::Value> object, void *parameter);
#elif (SWIG_V8_VERSION < 0x032112)
  void (*dtor) (v8::Isolate *isolate, v8::Persistent< v8::Object > *object, SWIGV8_Proxy *proxy);
#else
  void (*dtor) (const v8::WeakCallbackData < v8::Object, SWIGV8_Proxy > &data);
#endif
};

static v8::Persistent<v8::FunctionTemplate> SWIGV8_SWIGTYPE_Proxy_class_templ;

static int SWIG_V8_ConvertInstancePtr(v8::Handle<v8::Object> objRef, void** ptr, swig_type_info *info, int flags) {
  SWIGV8_SCOPE(scope);

  if(objRef->InternalFieldCount() < 1) return SWIG_ERROR;

#if (SWIG_V8_VERSION < 0x031900)
  v8::Handle<v8::Value> cdataRef = objRef->GetInternalField(0);
  SWIGV8_Proxy *cdata = static_cast<SWIGV8_Proxy *>(v8::External::Unwrap(cdataRef));
#else
  SWIGV8_Proxy *cdata = static_cast<SWIGV8_Proxy *>(objRef->GetAlignedPointerFromInternalField(0));
#endif

  if(cdata == NULL) {
    return SWIG_ERROR;
  }
  if(cdata->info != info) {
    swig_cast_info *tc = SWIG_TypeCheckStruct(cdata->info, info);
    if (!tc && cdata->info->name) {
      tc = SWIG_TypeCheck(cdata->info->name, info);
    }
    bool type_valid = tc != 0;
    if(!type_valid) {
      return SWIG_TypeError;
    }
  }
  *ptr = cdata->swigCObject;
  if(flags & SWIG_POINTER_DISOWN) {
    cdata->swigCMemOwn = false;
  }
  return SWIG_OK;
}

#if (SWIG_V8_VERSION < 0x031900)
static void SWIGV8_Proxy_DefaultDtor(v8::Persistent< v8::Value > object, void *parameter)
#elif (SWIG_V8_VERSION < 0x032112)
static void SWIGV8_Proxy_DefaultDtor(v8::Isolate *, v8::Persistent< v8::Object > *object, SWIGV8_Proxy *proxy)
#else
static void SWIGV8_Proxy_DefaultDtor(const v8::WeakCallbackData < v8::Object, SWIGV8_Proxy > &data)
#endif
{
#if (SWIG_V8_VERSION < 0x031900)
  SWIGV8_Proxy *proxy = static_cast<SWIGV8_Proxy *>(parameter);
#elif (SWIG_V8_VERSION < 0x032112)
  /* nothing */
#else
  SWIGV8_Proxy *proxy = data.GetParameter();
#endif

  delete proxy;
}

static int SWIG_V8_GetInstancePtr(v8::Handle<v8::Value> valRef, void** ptr) {
  if(!valRef->IsObject()) {
    return SWIG_TypeError;
  }
  v8::Handle<v8::Object> objRef = valRef.As<v8::Object>();

  if(objRef->InternalFieldCount() < 1) return SWIG_ERROR;

#if (SWIG_V8_VERSION < 0x031900)
  v8::Handle<v8::Value> cdataRef = objRef->GetInternalField(0);
  SWIGV8_Proxy *cdata = static_cast<SWIGV8_Proxy *>(v8::External::Unwrap(cdataRef));
#else
  SWIGV8_Proxy *cdata = static_cast<SWIGV8_Proxy *>(objRef->GetAlignedPointerFromInternalField(0));
#endif

  if(cdata == NULL) {
    return SWIG_ERROR;
  }

  *ptr = cdata->swigCObject;

  return SWIG_OK;
}

static void SWIGV8_SetPrivateData(v8::Handle<v8::Object> obj, void* ptr, swig_type_info *info, int flags) {
  SWIGV8_Proxy* cdata = new SWIGV8_Proxy();
  cdata->swigCObject = ptr;
  cdata->swigCMemOwn = (flags & SWIG_POINTER_OWN) ? 1 : 0;
  cdata->info = info;

#if (SWIG_V8_VERSION < 0x031900)
  obj->SetPointerInInternalField(0, cdata);
  cdata->handle = v8::Persistent<v8::Object>::New(obj);
#else
  obj->SetAlignedPointerInInternalField(0, cdata);
  cdata->handle.Reset(v8::Isolate::GetCurrent(), obj);
#endif

#if (SWIG_V8_VERSION < 0x031900)
  // clientdata must be set for owned data as we need to register the dtor
  if(cdata->swigCMemOwn && (SWIGV8_ClientData*)info->clientdata) {
    cdata->handle.MakeWeak(cdata, ((SWIGV8_ClientData*)info->clientdata)->dtor);
  } else {
    cdata->handle.MakeWeak(cdata, SWIGV8_Proxy_DefaultDtor);
  }
  cdata->handle.MarkIndependent();
#elif (SWIG_V8_VERSION < 0x032112)
  if(cdata->swigCMemOwn && (SWIGV8_ClientData*)info->clientdata) {
    cdata->handle.MakeWeak(v8::Isolate::GetCurrent(), cdata, ((SWIGV8_ClientData*)info->clientdata)->dtor);
  } else {
    cdata->handle.MakeWeak(v8::Isolate::GetCurrent(), cdata, SWIGV8_Proxy_DefaultDtor);
  }
#else
  if(cdata->swigCMemOwn && (SWIGV8_ClientData*)info->clientdata) {
    cdata->handle.SetWeak(cdata, ((SWIGV8_ClientData*)info->clientdata)->dtor);
  } else {
    cdata->handle.SetWeak(cdata, SWIGV8_Proxy_DefaultDtor);
  }
#endif

#if (SWIG_V8_VERSION < 0x032100)
  cdata->handle.MarkIndependent(v8::Isolate::GetCurrent());
#else
  cdata->handle.MarkIndependent();
#endif

}

static int SWIG_V8_ConvertPtr(v8::Handle<v8::Value> valRef, void** ptr, swig_type_info *info, int flags) {
  SWIGV8_SCOPE(scope);

  if(!valRef->IsObject()) {
    return SWIG_TypeError;
  }
  v8::Handle<v8::Object> objRef = valRef.As<v8::Object>();
  return SWIG_V8_ConvertInstancePtr(objRef, ptr, info, flags);
}

static v8::Handle<v8::Object> SWIG_V8_NewPointerObj(void *ptr, swig_type_info *info, int flags) {
  SWIGV8_SCOPE(scope);
  v8::Local<v8::FunctionTemplate> class_templ;

#if (SWIG_V8_VERSION < 0x031900)
  if(info->clientdata != 0) {
    class_templ = ((SWIGV8_ClientData*) info->clientdata)->class_templ;
  } else {
    class_templ = SWIGV8_SWIGTYPE_Proxy_class_templ;
  }
#else
  if(info->clientdata != 0) {
    class_templ = v8::Local<v8::FunctionTemplate>::New(iso, ((SWIGV8_ClientData*) info->clientdata)->class_templ);
  } else {
    class_templ = v8::Local<v8::FunctionTemplate>::New(iso, SWIGV8_SWIGTYPE_Proxy_class_templ);
  }
#endif

  v8::Local<v8::Object> result = class_templ->InstanceTemplate()->NewInstance();
  SWIGV8_SetPrivateData(result, ptr, info, flags);

  return SWIGV8_SCOPE_CLOSE(scope, result);
}

#define SWIG_ConvertPtr(obj, ptr, info, flags)    SWIG_V8_ConvertPtr(obj, ptr, info, flags)
#define SWIG_NewPointerObj(ptr, info, flags)      SWIG_V8_NewPointerObj(ptr, info, flags)

#define SWIG_ConvertInstance(obj, pptr, type, flags)    SWIG_V8_ConvertInstancePtr(obj, pptr, type, flags)
#define SWIG_NewInstanceObj(thisvalue, type, flags)     SWIG_V8_NewPointerObj(thisvalue, type, flags)

#define SWIG_ConvertFunctionPtr(obj, pptr, type)        SWIG_V8_ConvertPtr(obj, pptr, type, 0)
#define SWIG_NewFunctionPtrObj(ptr, type)               SWIG_V8_NewPointerObj(ptr, type, 0)

#define SWIG_GetInstancePtr(obj, ptr)    SWIG_V8_GetInstancePtr(obj, ptr)

#if (SWIG_V8_VERSION < 0x031900)
static v8::Handle<v8::Value> _SWIGV8_wrap_equals(const v8::Arguments &args) {
#else
static void _SWIGV8_wrap_equals(const v8::FunctionCallbackInfo<v8::Value>& args) {
#endif
  SWIGV8_SCOPE(scope);
  v8::Handle<v8::Value> jsresult;
  void *arg1 = (void *) 0 ;
  void *arg2 = (void *) 0 ;
  bool result;
  int res1;
  int res2;

  if(args.Length() != 1) SWIG_exception_fail(SWIG_ERROR, "Illegal number of arguments for equals.");

  res1 = SWIG_GetInstancePtr(args.Holder(), &arg1);
  if (!SWIG_IsOK(res1)) {
    SWIG_exception_fail(SWIG_ERROR, "Could not get pointer from 'this' object for equals.");
  }
  res2 = SWIG_GetInstancePtr(args[0], &arg2);
  if (!SWIG_IsOK(res2)) {
    SWIG_exception_fail(SWIG_ArgError(res2), "in method '" "equals" "', argument " "1"" of type '" "void *""'");
  }

  result = (bool)(arg1 == arg2);
#if (SWIG_V8_VERSION < 0x032410)
  jsresult =  v8::Boolean::New(result);
#else
  jsresult =  v8::Boolean::New(iso, result);
#endif

  SWIGV8_RETURN(jsresult);
  goto fail;
fail:
  SWIGV8_RETURN_UNDEF();
}

#if (SWIG_V8_VERSION < 0x031900)
static v8::Handle<v8::Value> _wrap_getCPtr(const v8::Arguments &args) {
#else
static void _wrap_getCPtr(const v8::FunctionCallbackInfo<v8::Value>& args) {
#endif
  SWIGV8_SCOPE(scope);
  v8::Handle<v8::Value> jsresult;
  void *arg1 = (void *) 0 ;
  long result;
  int res1;

  res1 = SWIG_GetInstancePtr(args.Holder(), &arg1);
  if (!SWIG_IsOK(res1)) {
    SWIG_exception_fail(SWIG_ArgError(res1), "in method '" "getCPtr" "', argument " "1"" of type '" "void *""'");
  }

  result = (long)arg1;
#if (SWIG_V8_VERSION < 0x032410)
  jsresult = v8::Number::New(result);
#else
  jsresult = v8::Number::New(iso, result);
#endif

  SWIGV8_RETURN(jsresult);
  goto fail;
fail:
  SWIGV8_RETURN_UNDEF();
}

/* ---------------------------------------------------------------------------
 * PackedData object
 *
 * ---------------------------------------------------------------------------*/

class SwigV8PackedData {
public:
  SwigV8PackedData(void *data, size_t size, swig_type_info *type): data(data), size(size), type(type) {};

  ~SwigV8PackedData() {
  };

  void* data;
  size_t size;
  swig_type_info *type;

  v8::Persistent<v8::Object> handle;
};

SWIGRUNTIMEINLINE
int SwigV8Packed_Check(v8::Handle<v8::Value> valRef) {
  SWIGV8_SCOPE(scope);
  if (!valRef->IsObject()) return false;
  v8::Handle<v8::Object> objRef = valRef.As<v8::Object>();
  if (objRef->InternalFieldCount() < 1) return false;
  v8::Handle<v8::Value> flag = objRef->GetHiddenValue(SWIGV8_SYMBOL("__swig__packed_data__"));
  return (flag->IsBoolean() && flag->BooleanValue());
}

SWIGRUNTIME
swig_type_info* SwigV8Packed_UnpackData(v8::Handle<v8::Value> valRef, void *ptr, size_t size) {
  if (SwigV8Packed_Check(valRef)) {
    SWIGV8_SCOPE(scope);
    SwigV8PackedData *sobj;

    v8::Handle<v8::Object> objRef = valRef.As<v8::Object>();

#if (SWIG_V8_VERSION < 0x031900)
    v8::Handle<v8::Value> cdataRef = objRef->GetInternalField(0);
    sobj = static_cast<SwigV8PackedData*>(v8::External::Unwrap(cdataRef));
#else
    sobj = static_cast<SwigV8PackedData*>(objRef->GetAlignedPointerFromInternalField(0));
#endif
    if (sobj == NULL || sobj->size != size) return 0;
    memcpy(ptr, sobj->data, size);
    return sobj->type;
  } else {
    return 0;
  }
}

SWIGRUNTIME
int SWIGV8_ConvertPacked(v8::Handle<v8::Value> valRef, void *ptr, size_t sz, swig_type_info *ty) {
  swig_type_info *to = SwigV8Packed_UnpackData(valRef, ptr, sz);
  if (!to) return SWIG_ERROR;
  if (ty) {
    if (to != ty) {
      /* check type cast? */
      swig_cast_info *tc = SWIG_TypeCheck(to->name,ty);
      if (!tc) return SWIG_ERROR;
    }
  }
  return SWIG_OK;
}

#if (SWIG_V8_VERSION < 0x031900)
static void _wrap_SwigV8PackedData_delete(v8::Persistent< v8::Value > object, void *parameter)
{
  SwigV8PackedData *cdata = static_cast<SwigV8PackedData *>(parameter);
#elif (SWIG_V8_VERSION < 0x032112)
static void _wrap_SwigV8PackedData_delete(v8::Isolate *isolate, v8::Persistent< v8::Object > * object, SwigV8PackedData *cdata)
{
#else
static void _wrap_SwigV8PackedData_delete(const v8::WeakCallbackData < v8::Object, SwigV8PackedData > &data)
{
  SwigV8PackedData *cdata = data.GetParameter();
#endif

  delete cdata;

#if (SWIG_V8_VERSION < 0x031900)
  object.Clear();
  object.Dispose();
#elif (SWIG_V8_VERSION < 0x032100)
  object->Dispose(isolate);
#elif (SWIG_V8_VERSION < 0x032112)
  object->Dispose();
#else
  /*nothing*/
#endif
}

SWIGRUNTIME
v8::Handle<v8::Value> SWIGV8_NewPackedObj(void *data, size_t size, swig_type_info *type) {
  SWIGV8_SCOPE(scope);

  SwigV8PackedData* cdata = new SwigV8PackedData(data, size, type);
#if (SWIG_V8_VERSION < 0x032410)
  v8::Local<v8::Object> obj = v8::Object::New();
  obj->SetHiddenValue(SWIGV8_SYMBOL("__swig__packed_data__"), v8::Boolean::New(true));
#else
  v8::Local<v8::Object> obj = v8::Object::New(iso);
  obj->SetHiddenValue(SWIGV8_SYMBOL("__swig__packed_data__"), v8::Boolean::New(iso, true));
#endif

#if (SWIG_V8_VERSION < 0x031900)
  obj->SetPointerInInternalField(0, cdata);
  cdata->handle = v8::Persistent<v8::Object>::New(obj);
#else
  obj->SetAlignedPointerInInternalField(0, cdata);
  cdata->handle.Reset(v8::Isolate::GetCurrent(), obj);
#endif

#if (SWIG_V8_VERSION < 0x031900)
  cdata->handle.MakeWeak(cdata, _wrap_SwigV8PackedData_delete);
  cdata->handle.MarkIndependent();
#elif (SWIG_V8_VERSION < 0x032112)
  cdata->handle.MakeWeak(v8::Isolate::GetCurrent(), cdata, _wrap_SwigV8PackedData_delete);
#else
  cdata->handle.SetWeak(cdata, _wrap_SwigV8PackedData_delete);
#endif

#if (SWIG_V8_VERSION < 0x032100)
  cdata->handle.MarkIndependent(v8::Isolate::GetCurrent());
#else
  cdata->handle.MarkIndependent();
#endif

  return SWIGV8_SCOPE_CLOSE(scope, obj);
}

#define SWIG_ConvertMember(obj, ptr, sz, ty)            SWIGV8_ConvertPacked(obj, ptr, sz, ty)
#define SWIG_NewMemberObj(ptr, sz, type)                SWIGV8_NewPackedObj(ptr, sz, type)


/* ---------------------------------------------------------------------------
 * Support for IN/OUTPUT typemaps (see Lib/typemaps/inoutlist.swg)
 *
 * ---------------------------------------------------------------------------*/

SWIGRUNTIME
v8::Handle<v8::Value> SWIGV8_AppendOutput(v8::Handle<v8::Value> result, v8::Handle<v8::Value> obj) {
  SWIGV8_SCOPE(scope);
  if (result->IsUndefined()) {
#if (SWIG_V8_VERSION < 0x032410)
    result = v8::Array::New();
#else
    result = v8::Array::New(iso);
#endif
  }
  v8::Local<v8::Array> arr = v8::Handle<v8::Array>::Cast(result);
  arr->Set(arr->Length(), obj);

  return SWIGV8_SCOPE_CLOSE(scope, arr);
}

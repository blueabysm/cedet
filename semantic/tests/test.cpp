/* Test file for C++ language.
 * Attempt to include as many aspects of the C++ language as possible.
 * Do not include things tested in test.c since that shares the
 * same language.
 *
 * $Id: test.cpp,v 1.12 2003-01-24 18:16:20 ponced Exp $
 *
 */

/* An include test */
#include "c++-test.hh"

#include <c++-test.hh>

double var1 = 1.2;

struct foo1 {
  int test;
};

struct foo2 : public foo1 {
  const int foo21(int a, int b);
  const int foo22(int a, int b) { return 1 }
};

/* Classes */
class class1 {
private:
  int var11;
  struct foo var12;
public:
  int p_var11;
  struct foo p_var12;
};

class i_class1 : public class1 {
private:
  int var11;
  struct foo var12;
public:
  int p_var11;
  struct foo p_var12;
};

class class2 {
private:
  int var21;
  struct foo var22;
public:
  int p_var21;
  struct foo p_var22;
};

class i_class2 : public class1, public class2 {
private:
  int var21;
  struct foo var22;
protected:
  int pt_var21;
public:
  int p_var21;
  struct foo p_var22;
};

class class3 {
  /* A class with strange things in it */
public:
  class3(); /* A constructor */
  enum embedded_foo_enum {
    a, b, c
  };
  struct embedded_bar_struct {
    int a;
    int b;
  };
  class embedded_baz_class {
    embedded_class();
    ~embedded_class();
  };
  ~class3(); /* destructor */
  
  /* Methods */
  int method_for_class3(int a, char b);
  int inline_method(int c) { return c; }

  /* Operators */
  class3& operator= (const class3& something);

  /* Funny declmods */
  const class3 * const method_const_ptr_ptr(const int * const argconst) const = 0;
};

class3::class3()
{
  /* Constructor outside the definition. */
}

int class3::method1_for_class3( int a, int &b)
{
  int c;
  class3 foo;

  // Completion testing line should find external members.
  a = foo.m;

  if (foo.fo) {
  }

  return 1;
}

char class3::method2_for_class3( int a, int b) throw ( exception1 )
{
  return 'a';
}

void *class3::method3_for_class3( int a, int b) throw ( exception1, exception2 )
{
  int q = a;
  return "Moose";
}

void *class3::method31_for_class3( int a, int b) throw ( )
{
  int q = a;
  return "Moose";
}

void *class3::method4_for_class3( int a, int b) reentrant
{
}

void *class3::method5_for_class3( int a, int b) const
{
}

// Stuff Klaus found.
// Inheritance w/out a specifying for public.
class class4 : class1 {
  // Pure virtual methods.
  void virtual print () const = 0;

};

class class5 : public virtual class4 {
  // Virtual inheritance
};

class class6 : class1 {
  // Mutable
  mutable int i;
};

/* Namespaces */
namespace namespace1 {
  void ns_method1() { }

  class n_class1 {
  public:
    void method11(int a) { }
  };

  /* This shouldn't parse due to missing semicolon. */
  class _n_class2 : public n_class1 {
    void n_c2_method1(int a, int b) { }
  }

  // Macros in the namespace
#define NSMACRO 1

  // Template in the namespace
  template<class T> T nsti1(const Foo& foo);
  template<> int nsti1<int>(const Foo& foo);
    
}

namespace namespace2 {

  using namespace1::n_class1;

}

/* Initializers */
void tinitializers1(): inita1(False),
		       inita2(False)
{
  inita1= 1;
}

/* How about Extern C type things. */

extern "C"
int extern_c_1(int a, int b)
{
  return 1;
}

extern "C" {

  int extern_c_2(int a, int b)
  {
    return 1;
  }

}

// Some operator stuff
class Action
{
  // Problems!! operator() and operator[] can not be parsed with semantic
  // 1.4.2 but with latest c.bnf
  virtual void operator()(int i, int j ) = 0;
  virtual String& operator[]() = 0;
  virtual void operator!() = 0;
  virtual void operator->() = 0;
};

// class with namespace qualified parents
class Multiinherit : public virtual POA::Parent,
                     public virtual POA::Parent1,
                     Parent
{
private:
  int i;

public:
  Multiinherit();
  ~Multiinherit();

  // method with a list of qualified exceptions
  void* throwtest()
    throw(Exception0,
          Testnamespace::Exception1,
          Testnamespace::Excpetion2,
          Testnamespace::testnamespace1::Exception3);
  
};

void*
Multiinherit::throwtest()
  throw (Exception0,
         Testnamespace::Exception1,
         Testnamespace::Excpetion2,
         Testnamespace::testnamespace1::Exception3)
{
  return;
}



/*
 * Ok, how about some template stuff.
 */
template <class CT, class container = vector<CT> >
const CT& max (const CT& a, const CT& b)
{
  return a < b ? b : a;
}

class TemplateUsingClass
{
  typedef map<long, long> TestClassMap;
  typedef TestClassMap::iterator iterator;

  map<int, int> mapclassvarthingy;
};

template<class T> T ti1(const Foo& foo);
template<> int ti1<int>(const Foo& foo);


// -----------------------------------
// Now some namespace and related stuff
// -----------------------------------

using CORBA::LEX::get_token;
using Namespace1;

using namespace POA::std;
using namespace Test;



namespace Parser
{
  namespace
  {
    using Lexer::get_test;
    string str = "";
  }
  
  namespace XXX
  {
    
    class Foobar : public virtual POA::Parent,
                   public virtual POA::Parent1
    {
      ini i;
    public:
      
      Foobar();
      ~Foobar();
    };
  }
  

  void test_function(int i);
    
};

// unnamed namespaces - even nested
namespace
{
  namespace
  {
    using Lexer::get_test;
    string str = "";
  }

  // some builtin types
  long long ll = 0;
  long double d = 0.0;
  unsigned test;
  unsigned long int uli = 0;
  signed si = 0;
  signed short ss = 0;  
  
  // expressions with namespace/class-qualifyiers
  ORB_var cGlobalOrb = ORB::_nil();
  ORB_var1 cGlobalOrb1 = ORB::_test;

  class Testclass
  {
    #define TEST 0
    ini i;

  public:

    Testclass();
    ~Testclass();
  };

  static void test_function(unsigned int i);

};


// outside method implementations which should be grouped to type Test
XXX&
Test::waiting()
{
  return;
}

void
Test::print()
{
  return;
}

// outside method implementations with namespaces which should be grouped to
// their complete (incl. namespace) types
void*
Parser::XXX::Foobar::wait(int i)
{
  return;
}

void*
Namespace1::Test::wait1(int i)
{
  return;
}

int
Namespace1::Test::waiting(int i)
{
  return;
}

// a class with some outside implementations which should all be grouped to
// this class declaration
class ClassWithExternals
{
private:
  int i;

public:
  ClassWithExternals();
  ~ClassWithExternals();
  void non_nil();
};


// Foobar is not displayed; seems that semantic tries to add this to the class
// Foobar but can not find/display it, because contained in the namespace above.
void
Foobar::non_nil()
{
  return;
}

// are correctly grouped to the ClassWithExternals class
void
ClassWithExternals::non_nil()
{
  String s = "l�dfjg dlfgkdlfkgjdl";
  return;
}

ClassWithExternals::ClassWithExternals()
{
  return;
}

void
ClassWithExternals::~ClassWithExternals()
{
  return;
}


// -------------------------------
// Now some macro and define stuff
// -------------------------------

#define TEST 0
#define TEST1 "String"

// The first backslash makes this macro unmatched syntax with semantic 1.4.2!
// With flexing \+newline as nothing all is working fine!
#define MZK_ENTER(METHOD) \
{ \
  CzkMethodLog lMethodLog(METHOD,"Framework");\
}

#define ZK_ASSERTM(METHOD,ASSERTION,MESSAGE) \
   { if(!(ASSERTION))\
      {\
	std::ostringstream lMesgStream; \
        lMesgStream << "Assertion failed: " \
	<< MESSAGE; \
        CzkLogManager::doLog(CzkLogManager::FATAL,"",METHOD, \
        "Assert",lMesgStream); \
        assert(ASSERTION);\
      }\
   }

// Test if not newline-backslashes are handled correctly
string s = "My \"quoted\" string";

// parsed fine as macro
#define FOO (arg) method(arg, "foo");

// With semantic 1.4.2 this parsed as macro BAR *and* function method.
// With latest c.bnf at least one-liner macros can be parsed correctly.
#define BAR (arg) CzkMessageLog method(arg, "bar");


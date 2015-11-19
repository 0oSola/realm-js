////////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#include "parser.hpp"

#include <iostream>

#include <pegtl.hh>
#include <pegtl/analyze.hh>
#include <pegtl/trace.hh>

using namespace pegtl;

namespace realm {
namespace parser {

// strings
struct unicode : list< seq< one< 'u' >, rep< 4, must< xdigit > > >, one< '\\' > > {};
struct escaped_char : one< '"', '\'', '\\', '/', 'b', 'f', 'n', 'r', 't', '0' > {};
struct escaped : sor< escaped_char, unicode > {};
struct unescaped : utf8::range< 0x20, 0x10FFFF > {};
struct chars : if_then_else< one< '\\' >, must< escaped >, unescaped > {};
struct dq_string_content : until< at< one< '"' > >, must< chars > > {};
struct dq_string : seq< one< '"' >, must< dq_string_content >, any > {};

struct sq_string_content : until< at< one< '\'' > >, must< chars > > {};
struct sq_string : seq< one< '\'' >, must< sq_string_content >, any > {};

// numbers
struct minus : opt< one< '-' > > {};
struct dot : one< '.' > {};

struct float_num : sor<
    seq< plus< digit >, dot, star< digit > >,
    seq< star< digit >, dot, plus< digit > >
> {};
struct hex_num : seq< one< '0' >, one< 'x', 'X' >, plus< xdigit > > {};
struct int_num : plus< digit > {};

struct number : seq< minus, sor< float_num, hex_num, int_num > > {};

struct true_value : pegtl_istring_t("true") {};
struct false_value : pegtl_istring_t("false") {};

// key paths
struct key_path : list< seq< sor< alpha, one< '_' > >, star< sor< alnum, one< '_', '-' > > > >, one< '.' > > {};

// argument
struct argument_index : plus< digit > {};
struct argument : seq< one< '$' >, must< argument_index > > {};

// expressions and operators
struct expr : sor< dq_string, sq_string, number, argument, true_value, false_value, key_path > {};

struct eq : sor< two< '=' >, one< '=' > > {};
struct noteq : pegtl::string< '!', '=' > {};
struct lteq : pegtl::string< '<', '=' > {};
struct lt : one< '<' > {};
struct gteq : pegtl::string< '>', '=' > {};
struct gt : one< '>' > {};
struct contains : pegtl_istring_t("contains") {};
struct begins : pegtl_istring_t("beginswith") {};
struct ends : pegtl_istring_t("endswith") {};

template<typename A, typename B>
struct pad_plus : seq< plus< B >, A, plus< B > > {};

struct padded_oper : pad_plus< sor< contains, begins, ends >, blank > {};
struct symbolic_oper : pad< sor< eq, noteq, lteq, lt, gteq, gt >, blank > {};

// predicates
struct comparison_pred : seq< expr, sor< padded_oper, symbolic_oper >, expr > {};

struct pred;
struct group_pred : if_must< one< '(' >, pad< pred, blank >, one< ')' > > {};
struct true_pred : pegtl_istring_t("truepredicate") {};
struct false_pred : pegtl_istring_t("falsepredicate") {};

struct not_pre : seq< sor< one< '!' >, pegtl_istring_t("not") > > {};
struct atom_pred : seq< opt< not_pre >, pad< sor< group_pred, true_pred, false_pred, comparison_pred >, blank > > {};

struct and_op : pad< sor< two< '&' >, pegtl_istring_t("and") >, blank > {};
struct or_op : pad< sor< two< '|' >, pegtl_istring_t("or") >, blank > {};

struct or_ext : if_must< or_op, pred > {};
struct and_ext : if_must< and_op, pred > {};
struct and_pred : seq< atom_pred, star< and_ext > > {};

struct pred : seq< and_pred, star< or_ext > > {};

// state
struct ParserState
{
    std::vector<Predicate *> predicate_stack;
    Predicate &current() {
        return *predicate_stack.back();
    }

    bool negate_next = false;

    void addExpression(Expression && exp)
    {
        if (current().type == Predicate::Type::Comparison) {
            current().cmpr.expr[1] = std::move(exp);
            predicate_stack.pop_back();
        }
        else {
            Predicate p(Predicate::Type::Comparison);
            p.cmpr.expr[0] = std::move(exp);
            if (negate_next) {
                p.negate = true;
                negate_next = false;
            }
            current().cpnd.sub_predicates.emplace_back(std::move(p));
            predicate_stack.push_back(&current().cpnd.sub_predicates.back());
        }
    }
};

// rules
template< typename Rule >
struct action : nothing< Rule > {};

#ifdef REALM_PARSER_PRINT_TOKENS
    #define DEBUG_PRINT_TOKEN(string) std::cout << string << std::endl
#else
    #define DEBUG_PRINT_TOKEN(string)
#endif

template<> struct action< and_ext >
{
    static void apply( const input & in, ParserState & state )
    {
        DEBUG_PRINT_TOKEN("<and>");

        // if we were put into an OR group we need to rearrange
        auto &current = state.current();
        if (current.type == Predicate::Type::Or) {
            auto &sub_preds = state.current().cpnd.sub_predicates;
            auto &second_last = sub_preds[sub_preds.size()-2];
            if (second_last.type == Predicate::Type::And) {
                // if we are in an OR group and second to last predicate group is
                // an AND group then move the last predicate inside
                second_last.cpnd.sub_predicates.push_back(std::move(sub_preds.back()));
                sub_preds.pop_back();
            }
            else {
                // otherwise combine last two into a new AND group
                Predicate pred(Predicate::Type::And);
                pred.cpnd.sub_predicates.emplace_back(std::move(second_last));
                pred.cpnd.sub_predicates.emplace_back(std::move(sub_preds.back()));
                sub_preds.pop_back();
                sub_preds.pop_back();
                sub_preds.push_back(std::move(pred));
            }
        }
    }
};

template<> struct action< or_ext >
{
    static void apply( const input & in, ParserState & state )
    {
        DEBUG_PRINT_TOKEN("<or>");

        // if already an OR group do nothing
        auto &current = state.current();
        if (current.type == Predicate::Type::Or) {
            return;
        }

        // if only two predicates in the group, then convert to OR
        auto &sub_preds = state.current().cpnd.sub_predicates;
        if (sub_preds.size()) {
            current.type = Predicate::Type::Or;
            return;
        }

        // split the current group into to groups which are ORed together
        Predicate pred1(Predicate::Type::And), pred2(Predicate::Type::And);
        pred1.cpnd.sub_predicates.insert(sub_preds.begin(), sub_preds.back());
        pred2.cpnd.sub_predicates.push_back(std::move(sub_preds.back()));

        current.type = Predicate::Type::Or;
        sub_preds.clear();
        sub_preds.emplace_back(std::move(pred1));
        sub_preds.emplace_back(std::move(pred2));
    }
};


#define EXPRESSION_ACTION(rule, type)                               \
template<> struct action< rule > {                                  \
    static void apply( const input & in, ParserState & state ) {    \
        DEBUG_PRINT_TOKEN(in.string());                             \
        state.addExpression(Expression(type, in.string())); }};

EXPRESSION_ACTION(dq_string_content, Expression::Type::String)
EXPRESSION_ACTION(sq_string_content, Expression::Type::String)
EXPRESSION_ACTION(key_path, Expression::Type::KeyPath)
EXPRESSION_ACTION(number, Expression::Type::Number)
EXPRESSION_ACTION(true_value, Expression::Type::True)
EXPRESSION_ACTION(false_value, Expression::Type::False)
EXPRESSION_ACTION(argument_index, Expression::Type::Argument)


template<> struct action< true_pred >
{
    static void apply( const input & in, ParserState & state )
    {
        DEBUG_PRINT_TOKEN(in.string());
        state.current().cpnd.sub_predicates.emplace_back(Predicate::Type::True);
    }
};

template<> struct action< false_pred >
{
    static void apply( const input & in, ParserState & state )
    {
        DEBUG_PRINT_TOKEN(in.string());
        state.current().cpnd.sub_predicates.emplace_back(Predicate::Type::False);
    }
};

#define OPERATOR_ACTION(rule, oper)                                 \
template<> struct action< rule > {                                  \
    static void apply( const input & in, ParserState & state ) {    \
        DEBUG_PRINT_TOKEN(in.string());                             \
        state.current().cmpr.op = oper; }};

OPERATOR_ACTION(eq, Predicate::Operator::Equal)
OPERATOR_ACTION(noteq, Predicate::Operator::NotEqual)
OPERATOR_ACTION(gteq, Predicate::Operator::GreaterThanOrEqual)
OPERATOR_ACTION(gt, Predicate::Operator::GreaterThan)
OPERATOR_ACTION(lteq, Predicate::Operator::LessThanOrEqual)
OPERATOR_ACTION(lt, Predicate::Operator::LessThan)
OPERATOR_ACTION(begins, Predicate::Operator::BeginsWith)
OPERATOR_ACTION(ends, Predicate::Operator::EndsWith)
OPERATOR_ACTION(contains, Predicate::Operator::Contains)

template<> struct action< one< '(' > >
{
    static void apply( const input & in, ParserState & state )
    {
        DEBUG_PRINT_TOKEN("<begin_group>");

        Predicate group(Predicate::Type::And);
        if (state.negate_next) {
            group.negate = true;
            state.negate_next = false;
        }

        state.current().cpnd.sub_predicates.emplace_back(std::move(group));
        state.predicate_stack.push_back(&state.current().cpnd.sub_predicates.back());
    }
};

template<> struct action< group_pred >
{
    static void apply( const input & in, ParserState & state )
    {
        DEBUG_PRINT_TOKEN("<end_group>");
        state.predicate_stack.pop_back();
    }
};

template<> struct action< not_pre >
{
    static void apply( const input & in, ParserState & state )
    {
        DEBUG_PRINT_TOKEN("<not>");
        state.negate_next = true;
    }
};

Predicate parse(const std::string &query)
{
    analyze< pred >();
    const std::string source = "user query";

    Predicate out_predicate(Predicate::Type::And);

    ParserState state;
    state.predicate_stack.push_back(&out_predicate);

    pegtl::parse< must< pred, eof >, action >(query, source, state);
    if (out_predicate.type == Predicate::Type::And && out_predicate.cpnd.sub_predicates.size() == 1) {
        return std::move(out_predicate.cpnd.sub_predicates.back());
    }
    return std::move(out_predicate);
}

}}



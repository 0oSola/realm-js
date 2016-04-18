////////////////////////////////////////////////////////////////////////////
//
// Copyright 2016 Realm Inc.
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

#pragma once

#include "js_collection.hpp"
#include "js_realm_object.hpp"
#include "js_results.hpp"
#include "js_types.hpp"
#include "js_util.hpp"

#include "shared_realm.hpp"
#include "list.hpp"
#include "parser.hpp"
#include "query_builder.hpp"

namespace realm {
namespace js {

template<typename T>
class List {
    using TContext = typename T::Context;
    using TObject = typename T::Object;
    using TValue = typename T::Value;
    using Object = Object<T>;
    using Value = Value<T>;
    using ReturnValue = ReturnValue<T>;

  public:
    static TObject create_instance(TContext, realm::List &);

    // properties
    static void get_length(TContext, TObject, ReturnValue &);
    static void get_index(TContext, TObject, uint32_t, ReturnValue &);
    static bool set_index(TContext, TObject, uint32_t, TValue);

    // methods
    static void push(TContext, TObject, size_t, const TValue[], ReturnValue &);
    static void pop(TContext, TObject, size_t, const TValue[], ReturnValue &);
    static void unshift(TContext, TObject, size_t, const TValue[], ReturnValue &);
    static void shift(TContext, TObject, size_t, const TValue[], ReturnValue &);
    static void splice(TContext, TObject, size_t, const TValue[], ReturnValue &);
    static void snapshot(TContext, TObject, size_t, const TValue[], ReturnValue &);
    static void filtered(TContext, TObject, size_t, const TValue[], ReturnValue &);
    static void sorted(TContext, TObject, size_t, const TValue[], ReturnValue &);
};

template<typename T>
struct ListClass : ClassDefinition<T, realm::List, CollectionClass<T>> {
    using List = List<T>;

    std::string const name = "List";

    MethodMap<T> const methods = {
        {"push", wrap<List::push>},
        {"pop", wrap<List::pop>},
        {"unshift", wrap<List::unshift>},
        {"shift", wrap<List::shift>},
        {"splice", wrap<List::splice>},
        {"snapshot", wrap<List::snapshot>},
        {"filtered", wrap<List::filtered>},
        {"sorted", wrap<List::sorted>},
    };

    PropertyMap<T> const properties = {
        {"length", {wrap<List::get_length>, nullptr}},
    };

    IndexPropertyType<T> const index_accessor = {wrap<List::get_index>, wrap<List::set_index>};
};

template<typename T>
typename T::Object List<T>::create_instance(TContext ctx, realm::List &list) {
    return create_object<T, ListClass<T>>(ctx, new realm::List(list));
}

template<typename T>
void List<T>::get_length(TContext ctx, TObject object, ReturnValue &return_value) {
    auto list = get_internal<T, ListClass<T>>(object);
    return_value.set((uint32_t)list->size());
}

template<typename T>
void List<T>::get_index(TContext ctx, TObject object, uint32_t index, ReturnValue &return_value) {
    auto list = get_internal<T, ListClass<T>>(object);
    auto realm_object = realm::Object(list->get_realm(), list->get_object_schema(), list->get(index));

    return_value.set(RealmObject<T>::create_instance(ctx, realm_object));
}

template<typename T>
bool List<T>::set_index(TContext ctx, TObject object, uint32_t index, TValue value) {
    auto list = get_internal<T, ListClass<T>>(object);
    list->set(ctx, value, index);
    return true;
}

template<typename T>
void List<T>::push(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count_at_least(argc, 1);

    auto list = get_internal<T, ListClass<T>>(this_object);
    for (size_t i = 0; i < argc; i++) {
        list->add(ctx, arguments[i]);
    }

    return_value.set((uint32_t)list->size());
}

template<typename T>
void List<T>::pop(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count(argc, 0);

    auto list = get_internal<T, ListClass<T>>(this_object);
    size_t size = list->size();
    if (size == 0) {
        list->verify_in_transaction();
        return_value.set_undefined();
    }
    else {
        size_t index = size - 1;
        auto realm_object = realm::Object(list->get_realm(), list->get_object_schema(), list->get(index));

        return_value.set(RealmObject<T>::create_instance(ctx, realm_object));
        list->remove(index);
    }
}

template<typename T>
void List<T>::unshift(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count_at_least(argc, 1);

    auto list = get_internal<T, ListClass<T>>(this_object);
    for (size_t i = 0; i < argc; i++) {
        list->insert(ctx, arguments[i], i);
    }

    return_value.set((uint32_t)list->size());
}

template<typename T>
void List<T>::shift(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count(argc, 0);

    auto list = get_internal<T, ListClass<T>>(this_object);
    if (list->size() == 0) {
        list->verify_in_transaction();
        return_value.set_undefined();
    }
    else {
        auto realm_object = realm::Object(list->get_realm(), list->get_object_schema(), list->get(0));

        return_value.set(RealmObject<T>::create_instance(ctx, realm_object));
        list->remove(0);
    }
}

template<typename T>
void List<T>::splice(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count_at_least(argc, 1);

    auto list = get_internal<T, ListClass<T>>(this_object);
    size_t size = list->size();
    long index = std::min<long>(Value::to_number(ctx, arguments[0]), size);
    if (index < 0) {
        index = std::max<long>(size + index, 0);
    }

    size_t remove;
    if (argc < 2) {
        remove = size - index;
    }
    else {
        remove = std::max<long>(Value::to_number(ctx, arguments[1]), 0);
        remove = std::min<long>(remove, size - index);
    }
    
    std::vector<TValue> removed_objects;
    removed_objects.reserve(remove);

    for (size_t i = 0; i < remove; i++) {
        auto realm_object = realm::Object(list->get_realm(), list->get_object_schema(), list->get(index));

        removed_objects.push_back(RealmObject<T>::create_instance(ctx, realm_object));
        list->remove(index);
    }
    for (size_t i = 2; i < argc; i++) {
        list->insert(ctx, arguments[i], index + i - 2);
    }

    return_value.set(Object::create_array(ctx, removed_objects));
}

template<typename T>
void List<T>::snapshot(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count(argc, 0);

    auto list = get_internal<T, ListClass<T>>(this_object);
    return_value.set(Results<T>::create_instance(ctx, *list, false));
}

template<typename T>
void List<T>::filtered(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count_at_least(argc, 1);

    auto list = get_internal<T, ListClass<T>>(this_object);
    return_value.set(Results<T>::create_filtered(ctx, *list, argc, arguments));
}

template<typename T>
void List<T>::sorted(TContext ctx, TObject this_object, size_t argc, const TValue arguments[], ReturnValue &return_value) {
    validate_argument_count(argc, 1, 2);

    auto list = get_internal<T, ListClass<T>>(this_object);
    return_value.set(Results<T>::create_sorted(ctx, *list, argc, arguments));
}
    
} // js
} // realm

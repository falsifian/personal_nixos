
function NixOS () {
  var env = Components.classes["@mozilla.org/process/environment;1"].
    getService(Components.interfaces.nsIEnvironment);

  if (env.exists("NIXOS"))
    this.nixos = env.get("NIXOS");
  if (env.exists("NIXOS_CONFIG"))
    this.config = env.get("NIXOS_CONFIG");
  if (env.exists("NIXPKGS"))
    this.nixpkgs = env.get("NIXPKGS");
  if (env.exists("mountPoint"))
    this.root = env.get("mountPoint");
  if (env.exists("NIXOS_OPTION"))
    this.optionBin = env.get("NIXOS_OPTION");
  this.option = new Option("options", this, null);
};

NixOS.prototype = {
  root: "",
  nixos: "/etc/nixos/nixos",
  nixpkgs: "/etc/nixos/nixpkgs",
  config: "/etc/nixos/configuration.nix",
  instantiateBin: "/var/run/current-system/sw/bin/nix-instantiate",
  optionBin: "/var/run/current-system/sw/bin/nixos-option",
  tmpFile: "nixos-gui",
  option: null
};

function Option (name, context, parent) {
  this.name = name;
  this.context_ = context;
  if (parent == null)
    this.path = "";
  else if (parent.path == "")
    this.path = name;
  else
    this.path = parent.path + "." + name;
};

Option.prototype = {
  load: function () {
    var env = "";
    env += "'NIXOS=" + this.context_.root + this.context_.nixos + "' ";
    env += "'NIXOS_PKGS=" + this.context_.root + this.context_.nixpkgs + "' ";
    env += "'NIXOS_CONFIG=" + this.context_.config + "' ";
    var out = makeTempFile(this.context_.tmpFile);
    var prog = this.context_.optionBin + " 2>&1 >" + out.path + " ";
    var args = " --xml " + this.path;

    runProgram(/*env + */ prog + args);
    var xml = readFromFile(out);
    out.remove(false);

    // jQuery does a stack overflow when converting a huge XML to a DOM.
    var dom = DOMParser().parseFromString(xml, "text/xml");
    var xmlAttrs = $("expr > attrs > attr", dom);

    this.isOption = xmlAttrs.first().attr("name") == "_isOption";

    if (!this.isOption)
      this.loadSubOptions(xmlAttrs);
    else
      this.loadOption(xmlAttrs);
    this.isLoaded = true;
  },

  loadSubOptions:  function (xmlAttrs) {
    var cur = this;
    var attrs = new Array();

    xmlAttrs.each(
      function (index) {
        var name = $(this).attr("name");
        var attr = new Option(name, cur.context_, cur);
        attrs.push(attr);
      }
    );

    this.subOptions = attrs;
  },

  optionAttributeMap: {
    _isOption: function (cur, v) { },
    value: function (cur, v) { cur.value = xml2nix($(v).children().first()); },
    default: function (cur, v) { cur.defaultValue = xml2nix($(v).children().first()); },
    example: function (cur, v) { cur.example = xml2nix($(v).children().first()); },
    description: function (cur, v) { cur.description = this.string(v); },
    typename: function (cur, v) { cur.typename = this.string(v); },
    options: function (cur, v) { cur.loadSubOptions($("attrs", v).children()); },
    declarations: function (cur, v) { cur.declarations = this.pathList(v); },
    definitions: function (cur, v) { cur.definitions = this.pathList(v); },

    string: function (v) {
      return $(v).children("string").first().attr("value");
    },

    pathList: function (v) {
      var list = [];
      $(v).children("list").first().children().each(
        function (idx) {
          list.push($(this).attr("value"));
        }
      );
      return list;
    }
  },


  loadOption: function (attrs) {
    var cur = this;

    attrs.each(
      function (index) {
        var name = $(this).attr("name");
        log("loadOption: " + name);
        cur.optionAttributeMap[name](cur, this);
      }
    );
  },

  // keep the context under which this option has been used.
  context_: null,
  // name of the option.
  name: "",
  // result of nixos-option.
  value: null,
  typename: null,
  defaultValue: null,
  example: null,
  description: "",
  declarations: [],
  definitions: [],
  // path to reach this option
  path: "",

  // list of options accessible from here.
  isLoaded: false,
  isOption: false,
  subOptions: []
};

var xml2nix_pptable = {
  attrs: function (node, depth, pp) {
    var out = "";
    out += "{";
    var children = node.children().not(
      function () {
        var name = $(this).attr("name");
        return name.charAt(0) == "_";
      }
    );
    if (children.lenght != 0)
    {
      depth += 1;
      children.each(
        function (idx) { out += pp.dispatch($(this), depth, pp); }
      );
      depth -= 1;
      out += this.indent(depth) + "";
    }
    else
      out += " ";
    out += "}";
    return out;
  },
  list: function (node, depth, pp) {
    var out = "";
    out += "[";
    var children = node.children();
    if (children.lenght != 0)
    {
      depth += 1;
      children.each(
        function (idx) { out += pp.dispatch($(this), depth, pp); }
      );
      depth -= 1;
      out += this.indent(depth);
    }
    else
      out += " ";
    out += "]";
    return out;
  },
  attr: function (node, depth, pp) {
    var name = node.attr("name");
    var out = "";
    var val = "";
    out += this.indent(depth);
    out += name + " = ";
    depth += 1;
    val = pp.dispatch(node.children().first(), depth, pp);
    out += val;
    if (val.indexOf("\n") != -1)
      out += this.indent(depth);;
    depth -= 1;
    out += ";";
    return out;
  },
  string: function (node, depth, pp) {
    return "\"" + node.attr("value") + "\"";
  },
  bool: function (node, depth, pp) {
    return node.attr("value");
  },
  null: function (node, depth, pp) {
    return "null";
  },
  function: function (node, depth, pp) {
    return "<function>";
  },
  unevaluated: function (node, depth, pp) {
    return "<unevaluated>";
  },

  dispatch: function (node, depth, pp) {
    for (var key in pp)
    {
      if(node.is(key))
      {
        log(this.indent(depth) + "dispatch: " + key);
        var out = pp[key](node, depth, pp);
        log(this.indent(depth) + "dispatch: => " + out);
        return out;
      }
    }
    return "<dispatch-error>";
  },
  indent: function (depth) {
    var ret = "\n";
    while (depth--)
      ret += "  ";
    return ret;
  }
};

function xml2nix(node) {
  var depth = 0;
  var pp = xml2nix_pptable;
  var out = pp.dispatch(node, depth, pp);
  log("pretty:\n" + out);
  return out;
}

/*
// Pretty print Nix values.
function nixPP(value, level)
{
  function indent(level) {  ret = ""; while (level--) ret+= "  "; return ret; }

  if (!level) level = 0;
  var ret = "<no match>";
  if (value.is("attrs")) {
    var content = "";
    value.children().each(function (){
      var name = $(this).attr("name");
      var value = nixPP($(this).children(), level + 1);
      content += indent(level + 1) + name + " = " + value + ";\n";
    });
    ret = "{\n" + content + indent(level) + "}";
  }
  else if (value.is("list")) {
    var content = "";
    value.children().each(function (){
      content += indent(level + 1) + "(" + nixPP($(this), level + 1) + ")\n";
    });
    ret = "[\n" + content + indent(level) + "]";
  }
  else if (value.is("bool"))
    ret = (value.attr("value") == "true");
  else if (value.is("string"))
    ret = '"' + value.attr("value") + '"';
  else if (value.is("path"))
    ret = value.attr("value");
  else if (value.is("int"))
    ret = parseInt(value.attr("value"));
  else if (value.is("derivation"))
    ret = value.attr("outPath");
  else if (value.is("function"))
    ret = "<function>";
  else {
    var content = "";
    value.children().each(function (){
      content += indent(level + 1) + "(" + nixPP($(this), level + 1) + ")\n";
    });
    ret = "<!--" + value.selector + "--><!--\n" + content + indent(level) + "-->";
  }
  return ret;
}

// Function used to reproduce the select operator on the XML DOM.
// It return the value contained in the targeted attribute.
function nixSelect(attrs, selector)
{
  var names = selector.split(".");
  var value = $(attrs);
  for (var i = 0; i < names.length; i++) {
    log(nixPP(value) + "." + names[i]);
    if (value.is("attrs"))
      value = value.children("attr[name='" + names[i] + "']").children();
    else {
      log("Cannot do an attribute selection.");
      break;
    }
  }

  log("nixSelect return: " + nixPP(value));

  var ret;
  if (value.is("attrs") || value.is("list"))
    ret = value;
  else if (value.is("bool"))
    ret = value.attr("value") == "true";
  else if (value.is("string"))
    ret = value.attr("value");
  else if (value.is("int"))
    ret = parseInt(value.attr("value"));
  else if (value.is("derivation"))
    ret = value.attr("outPath");
  else if (value.is("function"))
    ret = "<function>";

  return ret;
}
*/
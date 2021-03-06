library angular.tools.transformer.static_angular_generator;

import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:angular/tools/transformer/options.dart';
import 'package:code_transformers/resolver.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/refactor.dart' show TextEditTransaction;

class StaticAngularGenerator extends Transformer with ResolverTransformer {
  final TransformOptions options;

  StaticAngularGenerator(this.options, Resolvers resolvers) {
    this.resolvers = resolvers;
  }

  void applyResolver(Transform transform, Resolver resolver) {
    var asset = transform.primaryInput;

    var dynamicApp = resolver.getLibraryFunction('angular.app.factory.applicationFactory');
    if (dynamicApp == null) {
      // No dynamic app imports, exit.
      transform.addOutput(transform.primaryInput);
      return;
    }

    var id = asset.id;
    var lib = resolver.getLibrary(id);
    var transaction = resolver.createTextEditTransaction(lib);
    var unit = lib.definingCompilationUnit.computeNode();

    for (var directive in unit.directives) {
      if (directive is ImportDirective &&
          directive.uri.stringValue == 'package:angular/application_factory.dart') {
        var uri = directive.uri;
        transaction.edit(uri.beginToken.offset, uri.end,
            '\'package:angular/application_factory_static.dart\'');
      }
    }

    var dynamicToStatic = new _NgDynamicToStaticVisitor(
        dynamicApp, transaction, options.generateTemplateCache);
    unit.accept(dynamicToStatic);

    var generatedFilePrefix = '${path.url.basenameWithoutExtension(id.path)}';

    _addImport(transaction, unit,
        '${generatedFilePrefix}_static_expressions.dart',
        'generated_static_expressions');
    _addImport(transaction, unit,
        '${generatedFilePrefix}_static_metadata.dart',
        'generated_static_metadata');
    _addImport(transaction, unit,
        '${generatedFilePrefix}_static_type_to_uri_mapper.dart',
        'generated_static_type_to_uri_mapper');
    if (options.generateTemplateCache) {
      _addImport(transaction, unit,
          '${generatedFilePrefix}_generated_template_cache.dart',
          'generated_template_cache');
    }

    var printer = transaction.commit();
    var url = id.path.startsWith('lib/')
        ? 'package:${id.package}/${id.path.substring(4)}' : id.path;
    printer.build(url);
    transform.addOutput(new Asset.fromString(id, printer.text));
  }
}

/// Injects an import into the list of imports in the file.
void _addImport(TextEditTransaction transaction, CompilationUnit unit,
    String uri, String prefix) {
  var last = unit.directives.where((d) => d is ImportDirective).last;
  transaction.edit(last.end, last.end, '\nimport \'$uri\' as $prefix;');
}

class _NgDynamicToStaticVisitor extends GeneralizingAstVisitor {
  final Element ngDynamicFn;
  final TextEditTransaction transaction;
  final bool generateTemplateCache;
  _NgDynamicToStaticVisitor(this.ngDynamicFn, this.transaction,
      this.generateTemplateCache);

  visitMethodInvocation(MethodInvocation m) {
    if (m.methodName.bestElement == ngDynamicFn) {
      transaction.edit(m.methodName.beginToken.offset,
          m.methodName.endToken.end, 'staticApplicationFactory');

      var args = m.argumentList;
      transaction.edit(
          args.beginToken.offset + 1,
          args.end - 1,
          ['generated_static_metadata.typeAnnotations',
           'generated_static_expressions.getters',
           'generated_static_expressions.setters',
           'generated_static_expressions.symbols',
           'generated_static_type_to_uri_mapper.typeToUriMapper'
          ].join(', ')
        );
      if (generateTemplateCache) {
        transaction.edit(
            m.end,
            m.end,
            '.addModule(generated_template_cache.templateCacheModule)');
      }
    }
    super.visitMethodInvocation(m);
  }
}

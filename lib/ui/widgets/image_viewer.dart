import 'dart:ui';
import 'package:flutter/material.dart';

class ImageViewer extends StatelessWidget {
  const ImageViewer({
    required this.imageUrl,
    this.heroTag,
    super.key,
  });

  final String imageUrl;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Área de fundo com blur + leve escurecimento.
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),
          ),
          // Imagem central com Hero, que não fecha ao toque.
          Center(
            child: GestureDetector(
              onTap: () {}, // absorve o toque para não fechar
              child: Hero(
                tag: heroTag ?? imageUrl,
                child: FractionallySizedBox(
                  widthFactor: 0.9,
                  heightFactor: 0.9,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, _, __) {
                        return const Text(
                          'Falha ao carregar imagem',
                          style: TextStyle(color: Colors.white70),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


